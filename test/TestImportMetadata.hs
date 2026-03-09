module TestImportMetadata
  ( importMetadataTests
  ) where

import Compiler.AST (LawMetaAst(..), LawModuleAst(..), Sourced(..))
import Compiler.Compiler (compileLawModule)
import Compiler.Imports (resolveImports)
import Compiler.Parser (parseLawFile)
import Compiler.Templates (expandTemplates)
import NormativeGenerators (CapabilityIndex(..))
import Test.Tasty (testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

import qualified Data.List as L

importMetadataTests =
  testGroup
    "Import composition metadata preservation"
    [ testCase "imported articles retain source module metadata" testImportedMetadata
    ]

-- Load renewable_energy_case which imports multiple statutes/contracts.
-- Each imported module has its own law header (authority, enacted).
-- After resolveImports + expandTemplates, lawArticles should contain
-- Sourced articles where sourceMeta reflects the defining module.
testImportedMetadata :: IO ()
testImportedMetadata = do
  input <-
    readFile "lawlib/instantiations/renewable_energy_case.dsl"
  let parseResult = parseLawFile "lawlib/instantiations/renewable_energy_case.dsl" input
  case parseResult of
    Left _ -> assertBool "parse should succeed" False
    Right surfaceLawModule -> do
      resolved <- resolveImports surfaceLawModule
      case resolved of
        Left _ -> assertBool "resolveImports should succeed" False
        Right composedSurfaceLaw ->
          case expandTemplates composedSurfaceLaw of
            Left _ -> assertBool "expandTemplates should succeed" False
            Right lawModule -> do
              -- Root module has authority private
              let rootMeta = lawMeta lawModule
              assertBool
                "root module meta should have private authority"
                (lawAuthorityAst rootMeta == PrivatePower)
              -- Imported modules (e.g. renewable_energy_leasing) have authority legislative
              let articles = lawArticles lawModule
                  authorities = map (lawAuthorityAst . sourceMeta) articles
              assertBool
                "should have articles from legislative authority (imported statutes)"
                (LegislativePower `elem` authorities)
              -- Each article should have non-empty sourceMeta
              assertBool
                "all articles should have law name in sourceMeta"
                (all (not . null . lawNameAst . sourceMeta) articles)
              -- Each article should have a source path
              assertBool
                "all articles should have source path"
                (all (not . null . sourcePath) articles)
