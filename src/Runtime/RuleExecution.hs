{-# LANGUAGE GADTs #-}

module Runtime.RuleExecution
  ( conditionHolds
  , conditionWitnessDay
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

ruleSpecsToRules :: [RuleSpec] -> [Rule]
ruleSpecsToRules =
  map ruleSpecToRule

ruleSpecToRule :: RuleSpec -> Rule
ruleSpecToRule ruleSpec st =
  case conditionWitnessDay (ruleSpecCondition ruleSpec) st of
    Nothing -> st
    Just witnessDay ->
      let consequent = adjustConsequentTime witnessDay (ruleSpecConsequent ruleSpec)
      in if S.member consequent (normState st)
            then st
            else st { normState = S.insert consequent (normState st) }

conditionHolds :: ResolvedCondition -> SystemState -> Bool
conditionHolds condition st =
  case conditionWitnessDay condition st of
    Just _ -> True
    Nothing -> False

conditionWitnessDay :: ResolvedCondition -> SystemState -> Maybe Day
conditionWitnessDay condition st =
  case condition of
    ResolvedOwnershipCondition _ obj ->
      if S.member (P.Owned obj) (patrState st)
        then Just epochDate
        else Nothing
    ResolvedActionCondition act ->
      matchingActDay act (normState st)

adjustConsequentTime :: Day -> IndexedGen -> IndexedGen
adjustConsequentTime witnessDay indexed =
  indexed { time = max (time indexed) witnessDay }

matchingActDay :: Act Active -> Norm -> Maybe Day
matchingActDay act norm =
  case [ t | IndexedGen _ t (GAct visibleAct) <- S.toList norm, actsMatch act visibleAct ] of
    [] -> Nothing
    days -> Just (maximum days)

actsMatch :: Act Active -> Act r -> Bool
actsMatch expected visible =
  case visible of
    Simple _ _ _ -> show expected == show visible
    _ -> False
