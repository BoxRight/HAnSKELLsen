module TestBenchmark
  ( benchmarkTests
  ) where

import Compiler.Compiler (CompiledLawModule, compileLawModule, compiledRules)
import Compiler.Imports (resolveImports)
import Compiler.Parser (parseLawFile)
import Compiler.Scenario (compileScenarios)
import Compiler.Templates (expandTemplates)
import Data.Time.Calendar (fromGregorian)
import Logic (SystemState(..))
import Pretty.PrettyReport (generateAuditReport)
import Runtime.Audit (AuditResult(..), runAudit, runAuditFixpoint)
import Data.List (isInfixOf)
import qualified Data.Set as S
import Test.Tasty (testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

-- Run the renewable benchmark pipeline: parse, resolve, expand, compile, run audit.
-- Assert fixpoint idempotency and monotonicity on the resulting state.
benchmarkTests =
  testGroup
    "Renewable benchmark"
    [ testCase "benchmark compiles and runs with idempotent fixpoint" testBenchmarkIdempotency
    , testCase "benchmark state is monotonic" testBenchmarkMonotonicity
    , testCase "audit report contains DSL vocabulary" testReportVocabulary
    ]

-- Helper to run the full pipeline and get the audit result plus compiled module
withAuditResult :: (CompiledLawModule -> AuditResult -> IO ()) -> IO ()
withAuditResult k = do
  input <- readFile "lawlib/instantiations/renewable_energy_case.dsl"
  let parseResult = parseLawFile "lawlib/instantiations/renewable_energy_case.dsl" input
  case parseResult of
    Left _ -> assertBool "parse failed" False
    Right surfaceLawModule -> do
      resolved <- resolveImports surfaceLawModule
      case resolved of
        Left _ -> assertBool "resolveImports failed" False
        Right composedSurfaceLaw ->
          case expandTemplates composedSurfaceLaw of
            Left _ -> assertBool "expandTemplates failed" False
            Right lawModule -> do
              case compileLawModule lawModule of
                Left _ -> assertBool "compileLawModule failed" False
                Right compiled -> do
                  case compileScenarios lawModule of
                    Left _ -> assertBool "compileScenarios failed" False
                    Right scenarios -> do
                      case runAudit compiled scenarios (Just "ProjectDisruptionAndStepIn") (fromGregorian 2025 7 20) of
                        Left err -> assertBool ("runAudit failed: " ++ err) False
                        Right result -> k compiled result

testBenchmarkIdempotency :: IO ()
testBenchmarkIdempotency =
  withAuditResult $ \compiled result -> do
    let finalState = auditFinalState result
        dslRules = compiledRules compiled
        (reRunState, _) = runAuditFixpoint dslRules finalState
    -- Fixpoint idempotency: running again from final state yields the same state
    assertBool
      "fixpoint should be idempotent (re-run from final yields same state)"
      (reRunState == finalState)

testBenchmarkMonotonicity :: IO ()
testBenchmarkMonotonicity =
  withAuditResult $ \_ result -> do
    let seedState = auditSeedState result
        finalState = auditFinalState result
    assertBool
      "normState should be monotonic (seed ⊆ final)"
      (normState seedState `S.isSubsetOf` normState finalState)
    assertBool
      "patrState should be monotonic (seed ⊆ final)"
      (patrState seedState `S.isSubsetOf` patrState finalState)

testReportVocabulary :: IO ()
testReportVocabulary =
  withAuditResult $ \compiled result -> do
    let report = generateAuditReport compiled result
    -- Report should use domain vocabulary from DSL (grant, biodiversity, certification, etc.)
    assertBool
      "report should contain 'grant' (domain verb)"
      ("grant" `isInfixOf` report || "Grant" `isInfixOf` report)
    assertBool
      "report should contain 'biodiversity' (domain term)"
      ("biodiversity" `isInfixOf` report || "Biodiversity" `isInfixOf` report)
    assertBool
      "report should contain 'certification' (domain term)"
      ("certification" `isInfixOf` report || "Certification" `isInfixOf` report)
