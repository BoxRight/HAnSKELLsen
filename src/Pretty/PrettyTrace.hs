module Pretty.PrettyTrace
  ( explainIndexedGen
  , violationSummaryLines
  , prettyComplianceSummary
  , prettyDerivationStep
  , prettyRuleFire
  , prettyScenarioSeed
  ) where

import Capability (prettyCapability)
import NormativeGenerators
import Pretty.PrettyNorm (prettyIndexedGen)
import Runtime.Provenance

explainIndexedGen :: IndexedGen -> String
explainIndexedGen indexed =
  case gen indexed of
    GClaim _ ->
      "This claim was present in the source law or produced by a claim-producing rule."
    GObligation _ ->
      "This obligation was present in the source law or produced by an obligation-producing rule."
    GProhibition _ ->
      "This prohibition was present in the source law or produced by a prohibition-producing rule."
    GPrivilege _ ->
      "This privilege was present in the source law or produced by a privilege-producing rule."
    GFulfillment _ ->
      "A claimed act also appears in the state, so the engine marked it as fulfilled."
    GViolation _ ->
      "A counter-act occurred against an active obligation, so the engine marked a violation."
    GEnforceable _ ->
      "The opposite act occurred against a claim, so the engine marked the claim as enforceable."
    GStatute _ ->
      "A legislative act was lifted into a statute by the authority rules."
    Overridden _ ->
      "A higher-authority conflicting norm with suitable timing caused this norm to be overridden."
    GAct _ ->
      "This act is part of the current normative state."
    GEvent _ ->
      "This event was carried into the normative state from source facts or patrimony."

prettyScenarioSeed :: ScenarioSeed -> String
prettyScenarioSeed seed =
  "On "
    ++ show (seedDay seed)
    ++ ", scenario facts became visible: "
    ++ seedText seed

prettyRuleFire :: RuleFire -> String
prettyRuleFire firing =
  ruleOriginLabel (ruleOrigin firing)
    ++ " fired on "
    ++ show (witnessDay firing)
    ++ " because "
    ++ witnessLabel (witnessFacts firing)
    ++ actionText
    ++ renderConsequent (consequent firing)
    ++ "."
  where
    actionText
      | insertedNew firing = ", introducing "
      | otherwise = ", confirming existing "

prettyDerivationStep :: DerivationStep -> String
prettyDerivationStep step =
  case step of
    SeedStep seed -> prettyScenarioSeed seed
    RuleStep firing -> prettyRuleFire firing

prettyComplianceSummary :: ComplianceSummary -> [String]
prettyComplianceSummary summary =
  [ "Verdict: " ++ verdictLabel (complianceVerdict summary)
  , "Violations: " ++ show (length (violatedNorms summary))
  , "Fulfillments: " ++ show (length (fulfilledNorms summary))
  , "Enforceable claims: " ++ show (length (enforceableNorms summary))
  , "Pending obligations: " ++ show (length (pendingObligations summary))
  , "Active prohibitions: " ++ show (length (activeProhibitions summary))
  ] ++ violationSummaryLines summary

violationSummaryLines :: ComplianceSummary -> [String]
violationSummaryLines summary =
  case violatedNorms summary of
    [] -> []
    violations ->
      [ "Violation: " ++ renderConsequent violation
      | violation <- violations
      ]

ruleOriginLabel :: RuleOrigin -> String
ruleOriginLabel origin =
  case origin of
    DslRule name -> "Rule `" ++ name ++ "`"
    BuiltInRule name -> "Built-in rule `" ++ name ++ "`"

witnessLabel :: [FactRef] -> String
witnessLabel [] = "no recorded witness facts were preserved"
witnessLabel facts =
  joinWith "; " (map factRefLabel facts)

factRefLabel :: FactRef -> String
factRefLabel factRef =
  case factRef of
    NormFact indexed -> renderConsequent indexed
    PatrFact patr -> "patrimony fact " ++ show patr

renderConsequent :: IndexedGen -> String
renderConsequent indexed =
  prettyIndexedGen indexed

verdictLabel :: Verdict -> String
verdictLabel verdict =
  case verdict of
    Compliant -> "Compliant"
    NonCompliant -> "Non-compliant"

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [value] = value
joinWith separator (value : rest) = value ++ separator ++ joinWith separator rest
