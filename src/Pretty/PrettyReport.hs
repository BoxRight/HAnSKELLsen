module Pretty.PrettyReport
  ( generateReport
  ) where

import Capability (prettyCapability)
import Compiler.AST (lawAuthorityAst, lawEnactedAst, lawNameAst)
import Compiler.Compiler
import Data.Char (toLower)
import Data.List (sortOn)
import qualified Data.Set as S
import LegalOntology (Object, oName, pName)
import Logic (SystemState(..))
import NormativeGenerators
import Pretty.PrettyNorm
import Pretty.PrettyTrace

generateReport :: CompiledLawModule -> SystemState -> SystemState -> String
generateReport compiled initialState finalState =
  unlines $
    [ "Law Report"
    , ""
    , "Name: " ++ lawNameAst (compiledMetadata compiled)
    , "Authority: " ++ prettyCapability (lawAuthorityAst (compiledMetadata compiled))
    , "Enacted: " ++ show (lawEnactedAst (compiledMetadata compiled))
    , ""
    ]
      ++ sourceSection
      ++ procedureSection
      ++ ruleSection
      ++ derivedSection
      ++ finalStateSection
      ++ noteSection
  where
    initialFacts = sortIndexed (S.toList (normState initialState))
    finalFacts = sortIndexed (S.toList (activeNorms (normState finalState)))
    derivedFacts = filter (`S.notMember` normState initialState) finalFacts

    sourceSection =
      "Source norms:"
        : formatBulletList (map (renderNormBody . prettyIndexedGen) initialFacts)

    procedureSection
      | null (compiledProcedures compiled) = []
      | otherwise =
          [ ""
          , "Compiled procedures:"
          ]
            ++ formatBulletList (map prettyProcedure (compiledProcedures compiled))

    ruleSection
      | null (compiledRules compiled) = []
      | otherwise =
          [ ""
          , "Compiled rules:"
          ]
            ++ formatBulletList (map prettyRuleSpec (compiledRules compiled))

    derivedSection
      | null derivedFacts =
          [ ""
          , "Derived norms:"
          , "- No additional norms were derived by the current engine."
          ]
      | otherwise =
          [ ""
          , "Derived norms:"
          ]
            ++ concatMap prettyDerivedFact derivedFacts

    finalStateSection =
      [ ""
      , "Active normative state:"
      ]
        ++ formatBulletList (map (renderNormBody . prettyIndexedGen) finalFacts)

    noteSection =
      [ ""
      , "Notes:"
      , "- Procedures and named rules are compiled and validated in this slice."
      , "- Named rules are not yet executed as first-class engine rules."
      ]

prettyProcedure :: ProcedureIR -> String
prettyProcedure procedure =
  procedureIrName procedure ++ ": " ++ joinBranches (map prettyAct (procedureIrBranches procedure))

prettyRuleSpec :: RuleSpec -> String
prettyRuleSpec ruleSpec =
  ruleSpecName ruleSpec
    ++ ": If "
    ++ prettyCondition (ruleSpecCondition ruleSpec)
    ++ ", then "
    ++ renderNormBody (prettyIndexedGen (ruleSpecConsequent ruleSpec))

prettyCondition :: ResolvedCondition -> String
prettyCondition condition =
  case condition of
    ResolvedOwnershipCondition party obj ->
      pName party ++ " owns " ++ objectLabel obj

prettyDerivedFact :: IndexedGen -> [String]
prettyDerivedFact indexed =
  [ "- " ++ heading
  , renderNormBody body
  , "Reason:"
  , explainIndexedGen indexed
  ]
  where
    rendered = prettyIndexedGen indexed
    (heading, body) =
      case lines rendered of
        [] -> ("Derived norm", "")
        [line] -> ("Derived norm", line)
        firstLine : rest -> (firstLine, unlines rest)

formatBulletList :: [String] -> [String]
formatBulletList = map ("- " ++)

sortIndexed :: [IndexedGen] -> [IndexedGen]
sortIndexed = sortOn (\indexed -> (time indexed, capIndex indexed, show (gen indexed)))

joinBranches :: [String] -> String
joinBranches [] = ""
joinBranches [branch] = branch
joinBranches branches = foldr1 (\a b -> a ++ " or " ++ b) branches

stripHeading :: String -> String
stripHeading rendered =
  case lines rendered of
    [] -> ""
    [_] -> rendered
    _ : rest -> unlines rest

renderNormBody :: String -> String
renderNormBody =
  trimBlock . stripHeading

trimBlock :: String -> String
trimBlock =
  unwords . words

objectLabel :: Object -> String
objectLabel obj =
  "the " ++ lowercaseHead (oName obj)

lowercaseHead :: String -> String
lowercaseHead [] = []
lowercaseHead (x : xs) = toLower x : xs
