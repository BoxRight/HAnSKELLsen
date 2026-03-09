module Pretty.PrettyTrace
  ( explainIndexedGen
  , violationSummaryLines
  , prettyComplianceSummary
  , prettyDerivationStep
  , prettyRuleFire
  , prettyScenarioSeed
  ) where

import Capability (prettyCapability)
import LegalOntology (oName)
import NormativeGenerators
import Compiler.Compiler (DisplayVerbMap)
import Pretty.PrettyNorm (prettyIndexedGen, prettyIndexedGenWithDisplay)
import Runtime.Provenance
import qualified Patrimony as P

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

prettyRuleFire :: DisplayVerbMap -> RuleFire -> String
prettyRuleFire displayMap firing =
  ruleOriginLabel (ruleOrigin firing)
    ++ " fired on "
    ++ show (witnessDay firing)
    ++ " because "
    ++ witnessLabel displayMap (witnessFacts firing)
    ++ actionText
    ++ renderConsequentWithDisplay displayMap (consequent firing)
    ++ "."
  where
    actionText
      | insertedNew firing = ", introducing "
      | otherwise = ", confirming existing "

prettyDerivationStep :: DisplayVerbMap -> DerivationStep -> String
prettyDerivationStep displayMap step =
  case step of
    SeedStep seed -> prettyScenarioSeed seed
    RuleStep firing -> prettyRuleFire displayMap firing

prettyComplianceSummary :: DisplayVerbMap -> ComplianceSummary -> [String]
prettyComplianceSummary displayMap summary =
  [ "Verdict: " ++ verdictLabel (complianceVerdict summary)
  , "Violations: " ++ show (length (violatedNorms summary))
  , "Fulfillments: " ++ show (length (fulfilledNorms summary))
  , "Enforceable claims: " ++ show (length (enforceableNorms summary))
  , "Pending obligations: " ++ show (length (pendingObligations summary))
  , "Active prohibitions: " ++ show (length (activeProhibitions summary))
  ] ++ violationSummaryLines displayMap summary

violationSummaryLines :: DisplayVerbMap -> ComplianceSummary -> [String]
violationSummaryLines displayMap summary =
  case violatedNorms summary of
    [] -> []
    violations ->
      [ "Violation: " ++ renderConsequentWithDisplay displayMap violation
      | violation <- violations
      ]

ruleOriginLabel :: RuleOrigin -> String
ruleOriginLabel origin =
  case origin of
    DslRule name -> "Rule `" ++ name ++ "`"
    BuiltInRule name -> "Built-in rule `" ++ name ++ "`"

witnessLabel :: DisplayVerbMap -> [FactRef] -> String
witnessLabel _ [] = "no recorded witness facts were preserved"
witnessLabel displayMap facts =
  joinWith "; " (map (factRefLabel displayMap) facts)

factRefLabel :: DisplayVerbMap -> FactRef -> String
factRefLabel displayMap factRef =
  case factRef of
    NormFact indexed -> renderConsequentWithDisplay displayMap indexed
    PatrFact patr -> patrimonyLabel patr

renderConsequent :: IndexedGen -> String
renderConsequent indexed =
  prettyIndexedGen indexed

renderConsequentWithDisplay :: DisplayVerbMap -> IndexedGen -> String
renderConsequentWithDisplay displayMap indexed =
  prettyIndexedGenWithDisplay displayMap indexed

verdictLabel :: Verdict -> String
verdictLabel verdict =
  case verdict of
    Compliant -> "Compliant"
    NonCompliant -> "Non-compliant"

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [value] = value
joinWith separator (value : rest) = value ++ separator ++ joinWith separator rest

patrimonyLabel :: P.PatrimonyGen -> String
patrimonyLabel patrimonyFact =
  case patrimonyFact of
    P.Asset assetName -> "asset " ++ assetName
    P.Liability liabilityName -> "liability " ++ liabilityName
    P.Collateral collateralName -> "collateral " ++ collateralName
    P.Certification certificationName -> "certification " ++ certificationName
    P.ApprovedContractor contractorName -> "approved contractor " ++ contractorName
    P.Capability capabilityName -> "authority " ++ capabilityName ++ " is present"
    P.Owned obj -> "ownership of " ++ oName obj
