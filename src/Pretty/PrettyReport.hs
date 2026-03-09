module Pretty.PrettyReport
  ( generateReport
  , generateAuditReport
  ) where

import Capability (prettyCapability)
import Compiler.AST (lawAuthorityAst, lawEnactedAst, lawNameAst)
import Compiler.Compiler
import Compiler.Scenario
import Data.Char (toLower)
import Data.List (sortOn)
import qualified Data.Set as S
import Data.Time.Calendar (Day)
import LegalOntology (Object, oName, pName)
import Logic (SystemState(..))
import NormativeGenerators
import Pretty.PrettyNorm
import Pretty.PrettyTrace
import Runtime.Audit

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

generateAuditReport :: CompiledLawModule -> AuditResult -> String
generateAuditReport compiled auditResult =
  unlines $
    [ "Scenario Audit Report"
    , ""
    , "Name: " ++ lawNameAst (compiledMetadata compiled)
    , "Authority: " ++ prettyCapability (lawAuthorityAst (compiledMetadata compiled))
    , "Enacted: " ++ show (lawEnactedAst (compiledMetadata compiled))
    , "Audit date: " ++ show (auditDate auditResult)
    ]
      ++ scenarioHeader
      ++ sourceSection
      ++ procedureSection
      ++ ruleSection
      ++ scenarioSection
      ++ derivedSection
      ++ finalStateSection
      ++ noteSection
  where
    seedFacts = sortIndexed (S.toList (activeNorms (normState (auditSeedState auditResult))))
    finalFacts = sortIndexed (S.toList (activeNorms (normState (auditFinalState auditResult))))
    derivedFacts = filter (`S.notMember` normState (auditSeedState auditResult)) finalFacts

    scenarioHeader =
      case auditScenarioName auditResult of
        Just name -> ["Scenario: " ++ name, ""]
        Nothing -> [""]

    sourceSection =
      "Seed norms:"
        : formatBulletList (map (renderNormBody . prettyIndexedGen) seedFacts)

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
          , "Executable DSL rules:"
          ]
            ++ formatBulletList (map prettyRuleSpec (compiledRules compiled))

    scenarioSection
      | null (auditVisibleTimeline auditResult) =
          [ ""
          , "Visible scenario timeline:"
          , "- No scenario facts are active at this audit date."
          ]
      | otherwise =
          [ ""
          , "Visible scenario timeline:"
          ]
            ++ concatMap prettyTimelineEntry (auditVisibleTimeline auditResult)

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
      , "- DSL rules are executed alongside the built-in engine rules in this audit path."
      , "- Scenario slicing includes only facts visible on or before the audit date."
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
    ResolvedActionCondition act ->
      stripHeading (prettyAct act)

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

prettyTimelineEntry :: (Day, ScenarioDelta) -> [String]
prettyTimelineEntry (day, delta) =
  [ "- " ++ show day
  , renderNormBody (unlines (deltaDescriptions delta))
  ]

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
