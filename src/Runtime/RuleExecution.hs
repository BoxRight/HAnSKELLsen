{-# LANGUAGE GADTs #-}

module Runtime.RuleExecution
  ( ConditionWitness(..)
  , applyRuleSpecWithTrace
  , conditionHolds
  , conditionWitness
  , ruleSpecToRule
  , ruleSpecsToRules
  ) where

import Compiler.Compiler (IntrinsicArg(..), ResolvedAct(..), ResolvedCondition(..), RuleSpec(..))
import qualified Data.Set as S
import Data.Time.Calendar (Day)
import LegalOntology
import Logic (Rule, SystemState(..), epochDate)
import NormativeGenerators
import qualified Patrimony as P
import Runtime.Intrinsics (IntrinsicValue(..), defaultIntrinsicEnv, evaluateIntrinsic)
import Runtime.Provenance

data ConditionWitness = ConditionWitness
  { witnessAt :: Day
  , witnessSupportingFacts :: [FactRef]
  }
  deriving (Eq, Show)

ruleSpecsToRules :: [RuleSpec] -> [Rule]
ruleSpecsToRules =
  map ruleSpecToRule

ruleSpecToRule :: RuleSpec -> Rule
ruleSpecToRule ruleSpec st =
  case conditionWitness (ruleSpecCondition ruleSpec) st of
    Nothing -> st
    Just witnessInfo ->
      let consequent = adjustConsequentTime (witnessAt witnessInfo) (ruleSpecConsequent ruleSpec)
      in if S.member consequent (normState st)
            then st
            else st { normState = S.insert consequent (normState st) }

applyRuleSpecWithTrace :: RuleSpec -> SystemState -> (SystemState, [RuleFire])
applyRuleSpecWithTrace ruleSpec st =
  case conditionWitness (ruleSpecCondition ruleSpec) st of
    Nothing -> (st, [])
    Just witnessInfo ->
      let consequentFact = adjustConsequentTime (witnessAt witnessInfo) (ruleSpecConsequent ruleSpec)
          wasNew = S.notMember consequentFact (normState st)
          nextState =
            if wasNew
              then st { normState = S.insert consequentFact (normState st) }
              else st
          firing =
            RuleFire
              { ruleOrigin = DslRule (ruleSpecName ruleSpec)
              , witnessDay = witnessAt witnessInfo
              , witnessFacts = witnessSupportingFacts witnessInfo
              , consequent = consequentFact
              , insertedNew = wasNew
              }
      in (nextState, [firing])

conditionHolds :: ResolvedCondition -> SystemState -> Bool
conditionHolds condition st =
  case conditionWitness condition st of
    Just _ -> True
    Nothing -> False

conditionWitness :: ResolvedCondition -> SystemState -> Maybe ConditionWitness
conditionWitness condition st =
  case condition of
    ResolvedOwnershipCondition _ obj ->
      if S.member (P.Owned obj) (patrState st)
        then Just (ConditionWitness epochDate [PatrFact (P.Owned obj)])
        else Nothing
    ResolvedCapabilityCondition capability ->
      let fact = P.Capability (capabilityToken capability)
      in if S.member fact (patrState st)
            then Just (ConditionWitness epochDate [PatrFact fact])
            else Nothing
    ResolvedAssetCondition assetName ->
      let fact = P.Asset assetName
      in if S.member fact (patrState st)
            then Just (ConditionWitness epochDate [PatrFact fact])
            else Nothing
    ResolvedLiabilityCondition liabilityName ->
      let fact = P.Liability liabilityName
      in if S.member fact (patrState st)
            then Just (ConditionWitness epochDate [PatrFact fact])
            else Nothing
    ResolvedCollateralCondition collateralName ->
      let fact = P.Collateral collateralName
      in if S.member fact (patrState st)
            then Just (ConditionWitness epochDate [PatrFact fact])
            else Nothing
    ResolvedCertificationCondition certificationName ->
      let fact = P.Certification certificationName
      in if S.member fact (patrState st)
            then Just (ConditionWitness epochDate [PatrFact fact])
            else Nothing
    ResolvedApprovedContractorCondition contractorName ->
      let fact = P.ApprovedContractor contractorName
      in if S.member fact (patrState st)
            then Just (ConditionWitness epochDate [PatrFact fact])
            else Nothing
    ResolvedActionCondition act ->
      matchingResolvedActDay act (normState st)
    ResolvedEventCondition event ->
      matchingEventDay event (normState st)
    ResolvedIntrinsicPredicate name args ->
      resolveAndEvaluateIntrinsic name args (patrState st)
    ResolvedConjunction subConditions -> do
      witnesses <- traverse (\c -> conditionWitness c st) subConditions
      let combined = foldr1 laterWitness witnesses
          allFacts = concatMap witnessSupportingFacts witnesses
      pure (ConditionWitness (witnessAt combined) allFacts)

resolveAndEvaluateIntrinsic
  :: String
  -> [IntrinsicArg]
  -> P.PatrimonyState
  -> Maybe ConditionWitness
resolveAndEvaluateIntrinsic name args patr =
  case resolveIntrinsicArgs args patr of
    Nothing -> Nothing
    Just values ->
      case evaluateIntrinsic defaultIntrinsicEnv name values of
        Nothing -> Nothing
        Just False -> Nothing
        Just True -> Just (ConditionWitness epochDate [])

resolveIntrinsicArgs :: [IntrinsicArg] -> P.PatrimonyState -> Maybe [IntrinsicValue]
resolveIntrinsicArgs args patr =
  traverse (resolveArg patr) args
  where
    resolveArg patrState arg =
      case arg of
        ResolvedIntrinsicFactRef factName ->
          case lookupNumericFact factName patrState of
            Just v -> Just (NumericValue v)
            Nothing ->
              case lookupDateFact factName patrState of
                Just d -> Just (DateValue d)
                Nothing -> Nothing
        ResolvedIntrinsicLiteral d ->
          Just (NumericValue d)
        ResolvedIntrinsicDateLiteral day ->
          Just (DateValue day)

lookupNumericFact :: String -> P.PatrimonyState -> Maybe Double
lookupNumericFact name patr =
  case [v | P.NumericFact n v <- S.toList patr, n == name] of
    v : _ -> Just v
    [] -> Nothing

lookupDateFact :: String -> P.PatrimonyState -> Maybe Day
lookupDateFact name patr =
  case [d | P.DateFact n d <- S.toList patr, n == name] of
    d : _ -> Just d
    [] -> Nothing

adjustConsequentTime :: Day -> IndexedGen -> IndexedGen
adjustConsequentTime witnessDay indexed =
  indexed { time = max (time indexed) witnessDay }

matchingResolvedActDay :: ResolvedAct -> Norm -> Maybe ConditionWitness
matchingResolvedActDay resolvedAct norm =
  case resolvedAct of
    ResolvedActiveAct act -> matchingActiveActDay act norm
    ResolvedPassiveAct act -> matchingPassiveActDay act norm

matchingActiveActDay :: Act Active -> Norm -> Maybe ConditionWitness
matchingActiveActDay act norm =
  case
    [ ConditionWitness t [NormFact fact]
    | fact@(IndexedGen _ t (GAct visibleAct)) <- S.toList norm
    , activeActsMatch act visibleAct
    ] of
    [] -> Nothing
    witnesses -> Just (maximumWitness witnesses)

matchingPassiveActDay :: Act Passive -> Norm -> Maybe ConditionWitness
matchingPassiveActDay act norm =
  case
    [ ConditionWitness t [NormFact fact]
    | fact@(IndexedGen _ t (GAct visibleAct)) <- S.toList norm
    , passiveActsMatch act visibleAct
    ] of
    [] -> Nothing
    witnesses -> Just (maximumWitness witnesses)

matchingEventDay :: LegalEvent -> Norm -> Maybe ConditionWitness
matchingEventDay event norm =
  case
    [ ConditionWitness t [NormFact fact]
    | fact@(IndexedGen _ t (GEvent visibleEvent)) <- S.toList norm
    , eventMatches event visibleEvent
    ] of
    [] -> Nothing
    witnesses -> Just (maximumWitness witnesses)

eventMatches :: LegalEvent -> LegalEvent -> Bool
eventMatches expected visible =
  case (expected, visible) of
    (HumanAct e, HumanAct v) -> e == v
    (NaturalFact e, NaturalFact v) -> e == v
    _ -> False

activeActsMatch :: Act Active -> Act r -> Bool
activeActsMatch expected visible =
  case visible of
    Simple _ _ _ -> show expected == show visible
    _ -> False

passiveActsMatch :: Act Passive -> Act r -> Bool
passiveActsMatch expected visible =
  case visible of
    Counter _ _ _ -> show expected == show visible
    _ -> False

capabilityToken :: CapabilityIndex -> String
capabilityToken capability =
  case capability of
    BaseAuthority -> "baseauthority"
    PrivatePower -> "private"
    LegislativePower -> "legislative"
    JudicialPower -> "judicial"
    AdministrativePower -> "administrative"
    ConstitutionalPower -> "constitutional"

maximumWitness :: [ConditionWitness] -> ConditionWitness
maximumWitness [] = ConditionWitness epochDate []
maximumWitness witnesses =
  foldr1 laterWitness witnesses

laterWitness :: ConditionWitness -> ConditionWitness -> ConditionWitness
laterWitness left right
  | witnessAt left >= witnessAt right = left
  | otherwise = right
