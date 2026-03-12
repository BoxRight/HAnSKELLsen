module TestIRToDSL (tests) where

import Compiler.Compiler (compileLawModule)
import Compiler.Imports (resolveImports)
import Compiler.IRToDSL (irToDSL, IrDocument)
import Compiler.Parser (parseLawFile)
import Compiler.Scenario (compileScenarios)
import Compiler.Templates (expandTemplates)
import Data.Aeson (eitherDecode)
import qualified Data.ByteString.Lazy as LBS
import Data.List (isInfixOf)
import Runtime.QuantaleAnalysis
  ( generateQuantaleReportWith
  , emptyQuantaleOptions
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, assertFailure)
import System.Directory (doesFileExist)

irJsonPath :: FilePath
irJsonPath = "legal_ir_normative_complete.json"

tests :: TestTree
tests = testGroup "IRToDSL"
  [ testCase "IR JSON file exists"        testFileExists
  , testCase "IR JSON decodes"            testDecodes
  , testCase "Emitted DSL parses"         testParses
  , testCase "Emitted DSL compiles"       testCompiles
  , testCase "At least one act generator" testActGenerator
  ]

loadDoc :: IO IrDocument
loadDoc = do
  raw <- LBS.readFile irJsonPath
  case eitherDecode raw :: Either String [IrDocument] of
    Left err    -> assertFailure ("JSON decode error: " ++ err) >> undefined
    Right []    -> assertFailure "JSON array is empty" >> undefined
    Right (d:_) -> pure d

-- | Fully resolve the emitted DSL string through the same pipeline as Main.hs.
resolve :: String -> IO (Either String (IO ()))
resolve dslText =
  case parseLawFile "<generated>" dslText of
    Left bundle -> pure (Left ("DSL parse failed: " ++ show bundle))
    Right surfaceAst -> do
      resolved <- resolveImports surfaceAst
      case resolved of
        Left diags -> pure (Left ("Import resolution failed: " ++ unlines (map show diags)))
        Right composedSurface ->
          case expandTemplates composedSurface of
            Left diags -> pure (Left ("Template expansion failed: " ++ unlines (map show diags)))
            Right lawModule ->
              case compileLawModule lawModule of
                Left diags -> pure (Left ("Compile failed: " ++ unlines (map show diags)))
                Right compiled ->
                  case compileScenarios lawModule of
                    Left diags -> pure (Left ("Scenario compile failed: " ++ unlines (map show diags)))
                    Right scenarios -> pure (Right (pure ()))

testFileExists :: IO ()
testFileExists = do
  exists <- doesFileExist irJsonPath
  assertBool ("Expected file at " ++ irJsonPath) exists

testDecodes :: IO ()
testDecodes = do
  raw <- LBS.readFile irJsonPath
  case eitherDecode raw :: Either String [IrDocument] of
    Left err -> assertFailure ("JSON decode error: " ++ err)
    Right [] -> assertFailure "JSON array is empty"
    Right _  -> pure ()

testParses :: IO ()
testParses = do
  doc <- loadDoc
  let dslText = irToDSL doc
  case parseLawFile "<generated>" dslText of
    Left bundle ->
      assertFailure
        ( "DSL parse failed:\n"
          ++ show bundle
          ++ "\n\n--- Generated DSL ---\n"
          ++ dslText
        )
    Right _ -> pure ()

testCompiles :: IO ()
testCompiles = do
  doc <- loadDoc
  let dslText = irToDSL doc
  case parseLawFile "<generated>" dslText of
    Left bundle -> assertFailure ("DSL parse failed: " ++ show bundle)
    Right surfaceAst -> do
      resolved <- resolveImports surfaceAst
      case resolved of
        Left diags -> assertFailure ("Import resolution failed: " ++ unlines (map show diags))
        Right composedSurface ->
          case expandTemplates composedSurface of
            Left diags -> assertFailure ("Template expansion failed: " ++ unlines (map show diags))
            Right lawModule ->
              case compileLawModule lawModule of
                Left diags ->
                  assertFailure
                    ( "DSL compile failed:\n"
                      ++ unlines (map show diags)
                      ++ "\n--- Generated DSL ---\n"
                      ++ dslText
                    )
                Right _ -> pure ()

-- | Condition 3: At least one act generator — verified via the quantale report.
testActGenerator :: IO ()
testActGenerator = do
  doc <- loadDoc
  let dslText = irToDSL doc
  case parseLawFile "<generated>" dslText of
    Left bundle -> assertFailure ("DSL parse failed: " ++ show bundle)
    Right surfaceAst -> do
      resolved <- resolveImports surfaceAst
      case resolved of
        Left diags -> assertFailure ("Import resolution failed: " ++ unlines (map show diags))
        Right composedSurface ->
          case expandTemplates composedSurface of
            Left diags -> assertFailure ("Template expansion failed: " ++ unlines (map show diags))
            Right lawModule ->
              case compileLawModule lawModule of
                Left diags -> assertFailure ("DSL compile failed: " ++ unlines (map show diags))
                Right compiled ->
                  case compileScenarios lawModule of
                    Left diags -> assertFailure ("Scenario compile failed: " ++ unlines (map show diags))
                    Right scenarios -> do
                      let report = generateQuantaleReportWith compiled scenarios emptyQuantaleOptions
                      assertBool
                        ( "Expected at least one act generator.\n=== Quantale Report ===\n"
                          ++ take 500 report
                        )
                        ("Act generators: (none)" `notElem` lines report)
