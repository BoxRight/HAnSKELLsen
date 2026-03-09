module Main where

import Test.Tasty (defaultMain, testGroup)

import TestInvariants (invariantTests)
import TestImportMetadata (importMetadataTests)
import TestBenchmark (benchmarkTests)
import TestInstitutionalSemantics (institutionalSemanticsTests)
import TestIntrinsics (intrinsicTests)

main :: IO ()
main =
  defaultMain $
    testGroup
      "HAnSKELLsen"
      [ invariantTests
      , importMetadataTests
      , benchmarkTests
      , institutionalSemanticsTests
      , intrinsicTests
      ]
