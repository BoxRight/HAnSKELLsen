{-# LANGUAGE GADTs #-}

module Runtime.RuleExecution
  ( ConditionWitness(..)
  , applyRuleSpecWithTrace
  , conditionHolds
  , conditionWitness
  , ruleSpecToRule
  , ruleSpecsToRules
  ) where

import Compiler.Compiler
import qualified Data.Set as S
import Data.Time.Calendar (Day)
import LegalOntology
import Logic (Rule, SystemState(..), epochDate)
import NormativeGenerators
import qualified Patrimony as P
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
    ResolvedActionCondition act ->
      matchingActDay act (normState st)

adjustConsequentTime :: Day -> IndexedGen -> IndexedGen
adjustConsequentTime witnessDay indexed =
  indexed { time = max (time indexed) witnessDay }

matchingActDay :: Act Active -> Norm -> Maybe ConditionWitness
matchingActDay act norm =
  case
    [ ConditionWitness t [NormFact fact]
    | fact@(IndexedGen _ t (GAct visibleAct)) <- S.toList norm
    , actsMatch act visibleAct
    ] of
    [] -> Nothing
    witnesses -> Just (maximumWitness witnesses)

actsMatch :: Act Active -> Act r -> Bool
actsMatch expected visible =
  case visible of
    Simple _ _ _ -> show expected == show visible
    _ -> False

maximumWitness :: [ConditionWitness] -> ConditionWitness
maximumWitness [] = ConditionWitness epochDate []
maximumWitness witnesses =
  foldr1 laterWitness witnesses

laterWitness :: ConditionWitness -> ConditionWitness -> ConditionWitness
laterWitness left right
  | witnessAt left >= witnessAt right = left
  | otherwise = right
