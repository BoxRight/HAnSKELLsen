module Pretty.PrettyReport
  ( generateReport
  , generateAuditReport
  , prettyCondition
  ) where

import Capability (prettyCapability)
import Compiler.AST (lawAuthorityAst, lawEnactedAst, lawNameAst)
import Compiler.Compiler
import Compiler.Scenario
import Data.Char (toLower)
import Data.List (intercalate, sortOn)
import qualified Data.Set as S
import Data.Time.Calendar (Day)
import LegalOntology (LegalEvent(..), Object, oName, pName)
import Logic (SystemState(..))
import NormativeGenerators
import Compiler.Compiler (DisplayVerbMap, IntrinsicArg(..))
import Pretty.PrettyNorm
import Pretty.PrettyTrace
import Runtime.Audit
import Runtime.Provenance

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
        : formatBulletList (map (renderNormBody . prettyIndexedGenWithDisplay (compiledDisplayVerbMap compiled)) initialFacts)

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
            ++ formatBulletList (map (prettyRuleSpec (compiledDisplayVerbMap compiled)) (compiledRules compiled))

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
            ++ concatMap (prettyDerivedFact (compiledDisplayVerbMap compiled)) derivedFacts

    finalStateSection =
      [ ""
      , "Active normative state:"
      ]
        ++ formatBulletList (map (renderNormBody . prettyIndexedGenWithDisplay (compiledDisplayVerbMap compiled)) finalFacts)

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
      ++ ruleTraceSection
      ++ temporalTraceSection
      ++ derivedSection
      ++ complianceSection
      ++ classificationSection
      ++ finalStateSection
      ++ noteSection
  where
    seedFacts = sortIndexed (S.toList (activeNorms (normState (auditSeedState auditResult))))
    finalFacts = sortIndexed (S.toList (activeNorms (normState (auditFinalState auditResult))))
    derivedFacts = map consequent (filter insertedNew (auditRuleFirings auditResult))

    scenarioHeader =
      case auditScenarioName auditResult of
        Just name -> ["Scenario: " ++ name, ""]
        Nothing -> [""]

    sourceSection =
      "Seed norms:"
        : formatBulletList (map (renderNormBody . prettyIndexedGenWithDisplay (compiledDisplayVerbMap compiled)) seedFacts)

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
            ++ formatBulletList (map (prettyRuleSpec (compiledDisplayVerbMap compiled)) (compiledRules compiled))

    scenarioSection
      | null (auditScenarioSeeds auditResult) =
          [ ""
          , "Visible scenario timeline:"
          , "- No scenario facts are active at this audit date."
          ]
      | otherwise =
          [ ""
          , "Visible scenario timeline:"
          ]
            ++ formatBulletList (map prettyScenarioSeed (auditScenarioSeeds auditResult))

    ruleTraceSection
      | null (auditRuleFirings auditResult) =
          [ ""
          , "Rule firing trace:"
          , "- No DSL-derived rule firings were recorded."
          ]
      | otherwise =
          [ ""
          , "Rule firing trace:"
          ]
            ++ formatBulletList (map (prettyRuleFire (compiledDisplayVerbMap compiled)) (auditRuleFirings auditResult))

    temporalTraceSection
      | null filteredTrace =
          [ ""
          , "Temporal derivation trace:"
          , "- No derivation steps were recorded."
          ]
      | otherwise =
          [ ""
          , "Temporal derivation trace:"
          ]
            ++ concatMap (prettyTraceDay (compiledDisplayVerbMap compiled)) filteredTrace

    derivedSection
      | null derivedFacts =
          [ ""
          , "Derived norms:"
          , "- No additional norms were derived by DSL-traced rule execution."
          ]
      | otherwise =
          [ ""
          , "Derived norms:"
          ]
            ++ concatMap (prettyDerivedFact (compiledDisplayVerbMap compiled)) derivedFacts

    complianceSection =
      [ ""
      , "Compliance summary:"
      ]
        ++ formatBulletList (prettyComplianceSummary (compiledDisplayVerbMap compiled) (auditComplianceSummary auditResult))

    classificationSection
      | null (classifications (auditComplianceSummary auditResult)) =
          [ ""
          , "Audit classification:"
          , "- No violation classifications were produced."
          ]
      | otherwise =
          [ ""
          , "Audit classification:"
          ]
            ++ formatBulletList (map prettyClassification (classifications (auditComplianceSummary auditResult)))

    finalStateSection =
      [ ""
      , "Active normative state:"
      ]
        ++ groupedFinalState (compiledDisplayVerbMap compiled) finalFacts

    noteSection =
      [ ""
      , "Notes:"
      , "- DSL rules are executed alongside the built-in engine rules in this audit path."
      , "- Scenario slicing includes only facts visible on or before the audit date."
      , "- Built-in engine rules still affect the final state, but only DSL rule firings are explicitly traced in this slice."
      ]

    filteredTrace =
      filter (\(_, steps) -> not (null steps)) (map firstCauseSteps (auditDerivationTrace auditResult))

prettyProcedure :: ProcedureIR -> String
prettyProcedure procedure =
  procedureIrName procedure ++ ": " ++ joinBranches (map prettyAct (procedureIrBranches procedure))

prettyRuleSpec :: DisplayVerbMap -> RuleSpec -> String
prettyRuleSpec displayMap ruleSpec =
  ruleSpecName ruleSpec
    ++ ": If "
    ++ prettyCondition (ruleSpecCondition ruleSpec)
    ++ ", then "
    ++ renderNormBody (prettyIndexedGenWithDisplay displayMap (ruleSpecConsequent ruleSpec))

prettyCondition :: ResolvedCondition -> String
prettyCondition condition =
  case condition of
    ResolvedOwnershipCondition party obj ->
      pName party ++ " owns " ++ objectLabel obj
    ResolvedCapabilityCondition capability ->
      "authority " ++ show capability ++ " is present"
    ResolvedAssetCondition assetName ->
      "asset " ++ assetName ++ " is present"
    ResolvedLiabilityCondition liabilityName ->
      "liability " ++ liabilityName ++ " is present"
    ResolvedCollateralCondition collateralName ->
      "collateral " ++ collateralName ++ " is present"
    ResolvedCertificationCondition certificationName ->
      "certification " ++ certificationName ++ " is present"
    ResolvedApprovedContractorCondition contractorName ->
      "approved contractor " ++ contractorName ++ " is present"
    ResolvedActionCondition act ->
      prettyResolvedAct act
    ResolvedEventCondition event ->
      prettyLegalEvent event
    ResolvedIntrinsicPredicate name args ->
      name ++ " " ++ unwords (map prettyIntrinsicArg args)
    ResolvedConjunction subConditions ->
      intercalate " and " (map prettyCondition subConditions)

prettyIntrinsicArg :: IntrinsicArg -> String
prettyIntrinsicArg arg =
  case arg of
    ResolvedIntrinsicFactRef n -> n
    ResolvedIntrinsicLiteral d -> show d
    ResolvedIntrinsicDateLiteral day -> show day

prettyDerivedFact :: DisplayVerbMap -> IndexedGen -> [String]
prettyDerivedFact displayMap indexed =
  [ "- " ++ heading
  , renderNormBody body
  , "Reason:"
  , explainIndexedGen indexed
  ]
  where
    rendered = prettyIndexedGenWithDisplay displayMap indexed
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

prettyTraceDay :: DisplayVerbMap -> (Day, [DerivationStep]) -> [String]
prettyTraceDay displayMap (day, steps) =
  ("- " ++ show day) : map (prettyDerivationStep displayMap) steps

firstCauseSteps :: (Day, [DerivationStep]) -> (Day, [DerivationStep])
firstCauseSteps (day, steps) =
  (day, go S.empty steps)
  where
    go _ [] = []
    go seen (step : rest) =
      case step of
        SeedStep _ -> step : go seen rest
        RuleStep firing ->
          let key = consequent firing
          in if S.member key seen
                then go seen rest
                else step : go (S.insert key seen) rest

prettyClassification :: AuditClassification -> String
prettyClassification classification =
  "Authority: "
    ++ classificationAuthority classification
    ++ "; fiber: "
    ++ classificationFiber classification

groupedFinalState :: DisplayVerbMap -> [IndexedGen] -> [String]
groupedFinalState displayMap facts =
  concatMap renderGroup groups
  where
    groups =
      [ ("Claims", filter isClaim facts)
      , ("Obligations", filter isObligation facts)
      , ("Prohibitions", filter isProhibition facts)
      , ("Privileges", filter isPrivilege facts)
      , ("Statutes", filter isStatute facts)
      , ("Superseded norms", filter isOverriddenFact facts)
      , ("Violations", filter isViolation facts)
      , ("Fulfillments", filter isFulfillment facts)
      , ("Enforceable claims", filter isEnforceable facts)
      , ("Acts and events", filter isActOrEvent facts)
      ]

    renderGroup (_, []) = []
    renderGroup (title, groupedFacts) =
      ("- " ++ title ++ ":")
        : map (renderNormBody . prettyIndexedGenWithDisplay displayMap) groupedFacts

isClaim :: IndexedGen -> Bool
isClaim indexed =
  case gen indexed of
    GClaim _ -> True
    _ -> False

isObligation :: IndexedGen -> Bool
isObligation indexed =
  case gen indexed of
    GObligation _ -> True
    _ -> False

isProhibition :: IndexedGen -> Bool
isProhibition indexed =
  case gen indexed of
    GProhibition _ -> True
    _ -> False

isPrivilege :: IndexedGen -> Bool
isPrivilege indexed =
  case gen indexed of
    GPrivilege _ -> True
    _ -> False

isViolation :: IndexedGen -> Bool
isViolation indexed =
  case gen indexed of
    GViolation _ -> True
    _ -> False

isStatute :: IndexedGen -> Bool
isStatute indexed =
  case gen indexed of
    GStatute _ -> True
    _ -> False

isOverriddenFact :: IndexedGen -> Bool
isOverriddenFact indexed =
  case gen indexed of
    Overridden _ -> True
    _ -> False

isFulfillment :: IndexedGen -> Bool
isFulfillment indexed =
  case gen indexed of
    GFulfillment _ -> True
    _ -> False

isEnforceable :: IndexedGen -> Bool
isEnforceable indexed =
  case gen indexed of
    GEnforceable _ -> True
    _ -> False

isActOrEvent :: IndexedGen -> Bool
isActOrEvent indexed =
  case gen indexed of
    GAct _ -> True
    GEvent _ -> True
    _ -> False

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

prettyLegalEvent :: LegalEvent -> String
prettyLegalEvent event =
  case event of
    HumanAct desc -> "event " ++ desc
    NaturalFact desc -> "natural event " ++ desc

prettyResolvedAct :: ResolvedAct -> String
prettyResolvedAct resolvedAct =
  case resolvedAct of
    ResolvedActiveAct act -> stripHeading (prettyAct act)
    ResolvedPassiveAct act -> stripHeading (prettyAct act)
