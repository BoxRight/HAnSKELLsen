module TestIntrinsics
  ( intrinsicTests
  ) where

import Compiler.AST (ConditionAst (..), StandingFactAst (..))
import Compiler.Compiler (compileLawModule)
import Compiler.Imports (resolveImports)
import Compiler.Parser (parseConditionSentence, parseLawFile)
import Compiler.Scenario (compileScenarios)
import Compiler.Templates (expandTemplates)
import Data.Time.Calendar (Day, fromGregorian)
import Logic (SystemState(..))
import NormativeGenerators (Generator(..), IndexedGen(..))
import Runtime.Audit (AuditResult(..), runAudit)
import qualified Data.Set as S
import Test.Tasty (testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

intrinsicTests =
  testGroup
    "Numeric and temporal intrinsics"
    [ testCase "parse mixed condition: aboveThreshold and asset" testParseMixedCondition
    , testCase "numeric threshold: aboveThreshold production 10000 fires when production is 12000" testNumericThreshold
    , testCase "filing window valid: withinWindow fires when date is in range" testFilingWindowValid
    , testCase "filing window invalid: withinWindow does not fire when date is outside range" testFilingWindowInvalid
    , testCase "mixed condition: aboveThreshold and asset fires when both hold" testMixedCondition
    ]

runPipeline :: String -> Day -> IO (Either String AuditResult)
runPipeline scenarioName auditDay = do
  input <- readFile "test/fixtures/intrinsic_tests.dsl"
  let parseResult = parseLawFile "test/fixtures/intrinsic_tests.dsl" input
  case parseResult of
    Left e -> pure (Left ("parse failed: " ++ show e))
    Right surfaceLawModule -> do
      resolved <- resolveImports surfaceLawModule
      case resolved of
        Left e -> pure (Left ("resolveImports failed: " ++ show e))
        Right composedSurfaceLaw ->
          case expandTemplates composedSurfaceLaw of
            Left e -> pure (Left ("expandTemplates failed: " ++ show e))
            Right lawModule ->
              case compileLawModule lawModule of
                Left e -> pure (Left ("compileLawModule failed: " ++ show e))
                Right compiled ->
                  case compileScenarios lawModule of
                    Left e -> pure (Left ("compileScenarios failed: " ++ show e))
                    Right scenarios ->
                      case runAudit compiled scenarios (Just scenarioName) auditDay of
                        Left err -> pure (Left ("runAudit failed: " ++ err))
                        Right result -> pure (Right result)

testParseMixedCondition :: IO ()
testParseMixedCondition =
  case parseConditionSentence "aboveThreshold production 10000 and asset InsuranceClaimFiled is present" of
    Right (ConditionConjunctionAst [c1, c2]) -> do
      assertBool "first conjunct should be intrinsic" (case c1 of IntrinsicConditionAst _ _ -> True; _ -> False)
      case c2 of
        InstitutionalConditionAst (AssetFactAst "InsuranceClaimFiled") -> pure ()
        other -> assertBool ("second conjunct should be AssetFactAst, got: " ++ show other) False
    Right other -> assertBool ("expected ConditionConjunctionAst, got: " ++ show other) False
    Left err -> assertBool ("parse failed: " ++ err) False

testNumericThreshold :: IO ()
testNumericThreshold = do
  result <- runPipeline "NumericThresholdPass" (fromGregorian 2025 7 1)
  case result of
    Left err -> assertBool ("pipeline failed: " ++ err) False
    Right auditResult -> do
      let finalState = auditFinalState auditResult
          hasClaim = any (\(IndexedGen _ _ g) -> case g of GClaim _ -> True; _ -> False) (S.toList (normState finalState))
      assertBool "rule TaxEligibility should fire (claim derived from aboveThreshold production 10000)" hasClaim

testFilingWindowValid :: IO ()
testFilingWindowValid = do
  result <- runPipeline "FilingWindowValid" (fromGregorian 2025 5 1)
  case result of
    Left err -> assertBool ("pipeline failed: " ++ err) False
    Right auditResult -> do
      let finalState = auditFinalState auditResult
          hasObligation = any (\(IndexedGen _ _ g) -> case g of GObligation _ -> True; _ -> False) (S.toList (normState finalState))
      assertBool "rule FilingValid should fire (obligation derived from withinWindow)" hasObligation

testFilingWindowInvalid :: IO ()
testFilingWindowInvalid = do
  result <- runPipeline "FilingWindowInvalid" (fromGregorian 2025 6 1)
  case result of
    Left err -> assertBool ("pipeline failed: " ++ err) False
    Right auditResult -> do
      let finalState = auditFinalState auditResult
          hasObligation = any (\(IndexedGen _ _ g) -> case g of GObligation _ -> True; _ -> False) (S.toList (normState finalState))
      assertBool "rule FilingValid should NOT fire when filingDate is outside window" (not hasObligation)

testMixedCondition :: IO ()
testMixedCondition = do
  result <- runPipeline "MixedConditionPass" (fromGregorian 2025 6 3)
  case result of
    Left err -> assertBool ("pipeline failed: " ++ err) False
    Right auditResult -> do
      let finalState = auditFinalState auditResult
          hasObligation = any (\(IndexedGen _ _ g) -> case g of GObligation _ -> True; _ -> False) (S.toList (normState finalState))
      assertBool "rule MixedCondition should fire when both aboveThreshold and asset hold" hasObligation
