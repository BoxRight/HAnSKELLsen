{-# LANGUAGE GADTs #-}

module Runtime.Audit
  ( AuditResult(..)
  , lookupScenario
  , runAudit
  ) where

import Capability (prettyCapability)
import Compiler.Compiler
import Compiler.Scenario
import Data.List (foldl')
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Time.Calendar (Day)
import LegalOntology (Act(..), Active, Obligation(..))
import Logic (SystemState(..), activeToPassive, rules)
import NormativeGenerators
import qualified Patrimony as P
import Runtime.Provenance
import Runtime.RuleExecution

data AuditResult = AuditResult
  { auditScenarioName :: Maybe String
  , auditDate :: Day
  , auditVisibleTimeline :: [(Day, ScenarioDelta)]
  , auditScenarioSeeds :: [ScenarioSeed]
  , auditRuleFirings :: [RuleFire]
  , auditDerivationTrace :: [(Day, [DerivationStep])]
  , auditComplianceSummary :: ComplianceSummary
  , auditSeedState :: SystemState
  , auditFinalState :: SystemState
  }
  deriving (Eq, Show)

runAudit
  :: CompiledLawModule
  -> [CompiledScenario]
  -> Maybe String
  -> Day
  -> Either String AuditResult
runAudit compiled scenarios selectedScenarioName selectedAuditDate = do
  selectedScenario <- resolveScenario scenarios selectedScenarioName
  let visibleTimeline =
        maybe [] (scenarioTimelineUpTo selectedAuditDate) selectedScenario
      visibleFacts =
        maybe emptyScenarioDelta (scenarioFactsUpTo selectedAuditDate) selectedScenario
      seedState =
        SystemState
          { normState = S.fromList (compiledFacts compiled) `S.union` deltaNormFacts visibleFacts
          , patrState = P.emptyPatrimony `S.union` deltaPatrFacts visibleFacts
          }
      scenarioSeeds = buildScenarioSeeds visibleTimeline
      (finalState, rawRuleFirings) =
        runAuditFixpoint (compiledRules compiled) seedState
      ruleFirings = dedupeRuleFirings rawRuleFirings
      derivationTrace =
        buildDerivationTrace scenarioSeeds ruleFirings
      compliance = summarizeCompliance finalState
  pure $
    AuditResult
      { auditScenarioName = compiledScenarioName <$> selectedScenario
      , auditDate = selectedAuditDate
      , auditVisibleTimeline = visibleTimeline
      , auditScenarioSeeds = scenarioSeeds
      , auditRuleFirings = ruleFirings
      , auditDerivationTrace = derivationTrace
      , auditComplianceSummary = compliance
      , auditSeedState = seedState
      , auditFinalState = finalState
      }

lookupScenario :: [CompiledScenario] -> String -> Maybe CompiledScenario
lookupScenario scenarios wantedName =
  case filter (\scenario -> compiledScenarioName scenario == wantedName) scenarios of
    scenario : _ -> Just scenario
    [] -> Nothing

resolveScenario
  :: [CompiledScenario]
  -> Maybe String
  -> Either String (Maybe CompiledScenario)
resolveScenario scenarios maybeName =
  case maybeName of
    Nothing -> Right Nothing
    Just name ->
      case lookupScenario scenarios name of
        Just scenario -> Right (Just scenario)
        Nothing -> Left ("unknown scenario `" ++ name ++ "`")

runAuditFixpoint :: [RuleSpec] -> SystemState -> (SystemState, [RuleFire])
runAuditFixpoint dslRules =
  go []
  where
    go acc state =
      let builtInState = foldl' (\current ruleFn -> ruleFn current) state rules
          (nextState, firings) =
            foldl' applyDslRule (builtInState, []) dslRules
          acc' = acc ++ firings
      in if nextState == state
            then (nextState, acc')
            else go acc' nextState

    applyDslRule :: (SystemState, [RuleFire]) -> RuleSpec -> (SystemState, [RuleFire])
    applyDslRule (currentState, accFirings) ruleSpec =
      let (nextState, firings) = applyRuleSpecWithTrace ruleSpec currentState
      in (nextState, accFirings ++ firings)

buildScenarioSeeds :: [(Day, ScenarioDelta)] -> [ScenarioSeed]
buildScenarioSeeds =
  map buildSeed
  where
    buildSeed (day, delta) =
      ScenarioSeed
        { seedDay = day
        , seedText = unwords (deltaDescriptions delta)
        , seedFacts =
            map NormFact (S.toList (deltaNormFacts delta))
              ++ map PatrFact (S.toList (deltaPatrFacts delta))
        }

buildDerivationTrace :: [ScenarioSeed] -> [RuleFire] -> [(Day, [DerivationStep])]
buildDerivationTrace seeds firings =
  foldl' insertStep [] (seedSteps ++ ruleSteps)
  where
    seedSteps = [(seedDay seed, SeedStep seed) | seed <- seeds]
    ruleSteps = [(witnessDay fire, RuleStep fire) | fire <- firings]

    insertStep [] (day, step) = [(day, [step])]
    insertStep ((existingDay, steps) : rest) (day, step)
      | existingDay == day = (existingDay, steps ++ [step]) : rest
      | existingDay < day = (existingDay, steps) : insertStep rest (day, step)
      | otherwise = (day, [step]) : (existingDay, steps) : rest

dedupeRuleFirings :: [RuleFire] -> [RuleFire]
dedupeRuleFirings firings =
  M.elems (foldl' keepFirst M.empty firings)
  where
    keepFirst acc firing =
      M.insertWith keepExisting (ruleFireKey firing) firing acc

    keepExisting old _ = old

ruleFireKey :: RuleFire -> (RuleOrigin, Day, IndexedGen)
ruleFireKey firing =
  (ruleOrigin firing, witnessDay firing, consequent firing)

summarizeCompliance :: SystemState -> ComplianceSummary
summarizeCompliance finalState =
  ComplianceSummary
    { complianceVerdict =
        if null violationFacts
          then Compliant
          else NonCompliant
    , violatedNorms = violationFacts
    , fulfilledNorms = fulfillmentFacts
    , enforceableNorms = enforceableFacts
    , pendingObligations = pendingObligationFacts
    , activeProhibitions = prohibitionFacts
    , classifications = map classifyViolation violationFacts
    }
  where
    activeFacts = S.toList (activeNorms (normState finalState))
    violationFacts = filter isViolation activeFacts
    fulfillmentFacts = filter isFulfillment activeFacts
    enforceableFacts = filter isEnforceable activeFacts
    prohibitionFacts = filter isProhibition activeFacts
    pendingObligationFacts = filter isPendingObligation activeFacts

    isViolation indexed =
      case gen indexed of
        GViolation _ -> True
        _ -> False

    isFulfillment indexed =
      case gen indexed of
        GFulfillment _ -> True
        _ -> False

    isEnforceable indexed =
      case gen indexed of
        GEnforceable _ -> True
        _ -> False

    isProhibition indexed =
      case gen indexed of
        GProhibition _ -> True
        _ -> False

    isPendingObligation indexed =
      case gen indexed of
        GObligation (Obligation act) ->
          not (hasViolationFor act activeFacts) && not (hasFulfillmentFor act activeFacts)
        _ -> False

classifyViolation :: IndexedGen -> AuditClassification
classifyViolation indexed =
  AuditClassification
    { classificationAuthority = prettyCapability (capIndex indexed)
    , classificationFiber =
        case capIndex indexed of
          PrivatePower -> "intra-fiber"
          _ -> "institutional/public"
    }

hasViolationFor :: Act r -> [IndexedGen] -> Bool
hasViolationFor act facts =
  any matches facts
  where
    matches indexed =
      case gen indexed of
        GViolation counterAct ->
          case act of
            Simple _ _ _ -> show counterAct == show (activeToPassive act)
            _ -> False
        _ -> False

hasFulfillmentFor :: Act r -> [IndexedGen] -> Bool
hasFulfillmentFor act facts =
  any matches facts
  where
    matches indexed =
      case gen indexed of
        GFulfillment fulfilledAct -> show fulfilledAct == show act
        _ -> False
