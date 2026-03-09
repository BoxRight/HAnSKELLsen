{-# LANGUAGE GADTs #-}
module Logic where

import LegalOntology
import NormativeGenerators
import qualified Patrimony as P
import qualified Data.Set as S
import Data.Char (toLower)
import Data.Time.Calendar (Day, fromGregorian)

--------------------------------------------------
-- SYSTEM STATE (STAGE 4)
--------------------------------------------------

data SystemState = SystemState
  { normState :: Norm
  , patrState :: P.PatrimonyState
  } deriving (Eq, Show)

--------------------------------------------------
-- RULE TYPE
--------------------------------------------------

-- Old rule type (for backward compatibility)
type NormRule = Norm -> Norm

-- New rule type (works on system state)
type Rule = SystemState -> SystemState

--------------------------------------------------
-- APPLY RULES
--------------------------------------------------

applyRules :: [Rule] -> SystemState -> SystemState
applyRules rules state =
  foldl (\s r -> r s) state rules

--------------------------------------------------
-- FIXPOINT
--------------------------------------------------

fixpoint :: Eq a => (a -> a) -> a -> a
fixpoint f x =
  let x' = f x
  in if x' == x
        then x
        else fixpoint f x'

runSystem :: [Rule] -> SystemState -> SystemState
runSystem rules =
  fixpoint (applyRules rules)

--------------------------------------------------
-- STAGE 5: CAPABILITY HIERARCHY
--------------------------------------------------

-- Epoch date: represents "always valid" or permanent standing conditions
-- Used for capabilities and other institutional facts that don't have temporal bounds
epochDate :: Day
epochDate = fromGregorian 1 1 1

-- Capability hierarchy: defines which capabilities dominate others
-- constitutional > legislative > administrative > private
dominates :: CapabilityIndex -> CapabilityIndex -> Bool
dominates ConstitutionalPower _ = True
dominates LegislativePower AdministrativePower = True
dominates LegislativePower PrivatePower = True
dominates AdministrativePower PrivatePower = True
dominates a b = a == b

-- Check if two generators conflict (domain-specific)
-- A conflict occurs when two norms cannot both be valid simultaneously
conflicts :: Generator -> Generator -> Bool
-- Prohibition conflicts with privilege (can't both allow and forbid)
conflicts (GProhibition _) (GPrivilege _) = True
conflicts (GPrivilege _) (GProhibition _) = True
-- Obligation conflicts with prohibition (can't be required to do what's forbidden)
conflicts (GObligation _) (GProhibition _) = True
conflicts (GProhibition _) (GObligation _) = True
-- Two conflicting obligations (simplified: any two obligations conflict)
-- In practice, you'd want more sophisticated conflict detection
conflicts (GObligation _) (GObligation _) = False  -- Allow multiple obligations
-- Overridden generators don't conflict (they're already marked as overridden)
conflicts (Overridden _) _ = False
conflicts _ (Overridden _) = False
-- Add more conflict patterns as needed
conflicts _ _ = False

--------------------------------------------------
-- RULE WRAPPERS (STAGE 4)
--------------------------------------------------

-- Wrapper to adapt old Norm -> Norm rules to SystemState -> SystemState
normRuleWrapper :: NormRule -> Rule
normRuleWrapper r st =
  st { normState = r (normState st) }

--------------------------------------------------
-- EXAMPLE DOMAIN RULE
--------------------------------------------------

-- Claim over a thing implies claim over delivery
objectClaimToDelivery :: NormRule
objectClaimToDelivery state =
  S.foldr derive state state
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen capIdx time g) acc =
      case g of
        GClaim (Claim act) ->
          case act of
            Simple actor obj target ->
              case oSubtype obj of
                ThingSubtype _ ->
                  let deliveryAct = Simple actor (deliveryObject obj) target
                      newGen = IndexedGen capIdx time (GClaim (Claim deliveryAct))
                  in if S.member newGen acc
                        then acc
                        else S.insert newGen acc
                _ -> acc
            Counter actor obj target ->
              case oSubtype obj of
                ThingSubtype _ ->
                  let deliveryAct = Counter actor (deliveryObject obj) target
                      newGen = IndexedGen capIdx time (GClaim (Claim deliveryAct))
                  in if S.member newGen acc
                        then acc
                        else S.insert newGen acc
                _ -> acc
            _ -> acc  -- Seq and Par are not handled (could be added if needed)
        _ -> acc

--------------------------------------------------
-- DELIVERY TRANSFORMATION
--------------------------------------------------

deliveryOf :: Act r -> Act r
deliveryOf act =
  case act of
    Simple p obj t ->
      Simple p (deliveryObject obj) t
    Counter p obj t ->
      Counter p (deliveryObject obj) t
    Seq xs ->
      Seq (map deliveryOf xs)
    Par xs ->
      Par (S.map deliveryOf xs)

deliveryObject :: Object -> Object
deliveryObject obj =
  obj
    { oSubtype = ServiceSubtype (Performance (Just obj))
    }

--------------------------------------------------
-- ACT NEGATION
--------------------------------------------------

-- Convert Active act to Passive (counter-act)
activeToPassive :: Act Active -> Act Passive
activeToPassive act =
  case act of
    Simple p obj t -> Counter p obj t
    Seq xs -> Seq (map activeToPassive xs)
    Par xs -> Par (S.map activeToPassive xs)

-- Convert Passive act to Active (counter-act)  
-- (Not currently used, but available for future rules)
passiveToActive :: Act Passive -> Act Active
passiveToActive act =
  case act of
    Counter p obj t -> Simple p obj t
    Seq xs -> Seq (map passiveToActive xs)
    Par xs -> Par (S.map passiveToActive xs)

--------------------------------------------------
-- STAGE 3: DERIVED NORMATIVE STATUSES
--------------------------------------------------

-- Claim Fulfillment: If an act that someone has a claim to actually occurs
claimFulfilled :: NormRule
claimFulfilled state =
  S.foldr derive state state
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen capIdx time g) acc =
      case g of
        GClaim (Claim act) ->
          case act of
            Simple _ _ _ ->  -- Act Active
              if S.member (IndexedGen capIdx time (GAct act)) acc
                 then let newGen = IndexedGen capIdx time (GFulfillment act)
                      in if S.member newGen acc
                            then acc
                            else S.insert newGen acc
                 else acc
            Counter _ _ _ ->  -- Act Passive - fulfillment not applicable
              acc
            _ -> acc  -- Seq and Par not handled
        _ -> acc

-- Claim Becomes Enforceable: If the opposite of the act occurs
claimEnforceable :: NormRule
claimEnforceable state =
  S.foldr derive state state
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen capIdx time g) acc =
      case g of
        GClaim (Claim act) ->
          case act of
            Simple _ _ _ ->  -- Act Active
              let counter = activeToPassive act
              in if S.member (IndexedGen capIdx time (GAct counter)) acc
                    then let newGen = IndexedGen capIdx time (GEnforceable act)
                         in if S.member newGen acc
                               then acc
                               else S.insert newGen acc
                    else acc
            Counter _ _ _ ->  -- Act Passive - enforceability not applicable
              acc
            _ -> acc  -- Seq and Par not handled
        _ -> acc

-- Obligation Violation: If an obligation exists and the counter-act occurs
obligationViolation :: NormRule
obligationViolation state =
  S.foldr derive state state
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen capIdx time g) acc =
      case g of
        GObligation (Obligation act) ->
          case act of
            Simple _ _ _ ->  -- Act Active
              let counter = activeToPassive act
              in if S.member (IndexedGen capIdx time (GAct counter)) acc
                    then let newGen = IndexedGen capIdx time (GViolation counter)
                         in if S.member newGen acc
                               then acc
                               else S.insert newGen acc
                    else acc
            Counter _ _ _ ->  -- Act Passive - violation not applicable
              acc
            _ -> acc  -- Seq and Par not handled
        _ -> acc

--------------------------------------------------
-- STAGE 4: CROSS-DOMAIN RULES
--------------------------------------------------

-- Normative → Patrimony Mapping (g map)
-- Institutional consequences generate patrimonial effects
normToPatrimony :: Rule
normToPatrimony st =
  let norm = normState st
      patr = patrState st
      newPatr = S.foldr derive patr norm
  in st { patrState = newPatr }
  where
    derive :: IndexedGen -> P.PatrimonyState -> P.PatrimonyState
    derive (IndexedGen capIdx t g) acc =
      case g of
        GViolation act ->
          let newGen = P.Liability ("breach:" ++ show capIdx ++ ":" ++ show act)
          in if S.member newGen acc
                then acc
                else S.insert newGen acc
        GFulfillment act ->
          let newGen = P.Asset ("performance:" ++ show capIdx ++ ":" ++ show act)
          in if S.member newGen acc
                then acc
                else S.insert newGen acc
        _ -> acc

-- Patrimony → Normative Mapping (f map)
-- Capabilities enable institutional participation
-- Capabilities are standing conditions (permanent facts), not dated events
patrimonyToNorm :: Rule
patrimonyToNorm st =
  let norm = normState st
      patr = patrState st
      newNorm = S.foldr derive norm patr
  in st { normState = newNorm }
  where
    derive :: P.PatrimonyGen -> Norm -> Norm
    derive p acc =
      case p of
        P.Capability cap ->
          -- Map capability string to capability index
          -- Use epoch date to represent permanent standing institutional conditions
          let capIdx = capabilityFromString cap
              newGen = IndexedGen capIdx epochDate (GEvent (HumanAct ("capability:" ++ cap)))
          in if S.member newGen acc
                then acc
                else S.insert newGen acc
        P.Owned obj ->
          -- Ownership is also a standing condition (valid from epoch)
          let newGen = IndexedGen PrivatePower epochDate (GEvent (HumanAct ("owns:" ++ show obj)))
          in if S.member newGen acc
                then acc
                else S.insert newGen acc
        _ -> acc

-- Helper to map capability strings to indices
capabilityFromString :: String -> CapabilityIndex
capabilityFromString s
  | "legislative" `elem` words (map toLower s) = LegislativePower
  | "judicial" `elem` words (map toLower s) = JudicialPower
  | "administrative" `elem` words (map toLower s) = AdministrativePower
  | "constitutional" `elem` words (map toLower s) = ConstitutionalPower
  | otherwise = PrivatePower

--------------------------------------------------
-- STAGE 5: AUTHORITY RULES
--------------------------------------------------

-- Legislative rule: Acts under legislative power create statutes
legislationRule :: Rule
legislationRule st =
  let norm = normState st
      patr = patrState st
      -- Check if legislative capability exists
      hasLegislative = S.member (P.Capability "legislative_power") patr
      newNorm = if hasLegislative
                   then S.foldr derive norm norm
                   else norm
  in st { normState = newNorm }
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen LegislativePower t (GAct act)) acc =
      case act of
        Simple _ _ _ ->  -- Act Active
          let newGen = IndexedGen LegislativePower t (GStatute act)
          in if S.member newGen acc
                then acc
                else S.insert newGen acc
        _ -> acc
    derive _ acc = acc

-- Cross-fiber rule: Statutes create obligations in private domain
statuteCreatesObligation :: Rule
statuteCreatesObligation st =
  let norm = normState st
      newNorm = S.foldr derive norm norm
  in st { normState = newNorm }
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen LegislativePower t (GStatute act)) acc =
      let newGen = IndexedGen PrivatePower t (GObligation (Obligation act))
      in if S.member newGen acc
            then acc
            else S.insert newGen acc
    derive _ acc = acc

--------------------------------------------------
-- HIERARCHY AND TEMPORAL RULES
--------------------------------------------------

-- Override rule: Higher authority can override lower authority norms
-- This preserves the historical record by marking norms as overridden rather than deleting them
overrideRule :: Rule
overrideRule st =
  let norm = normState st
      newNorm = S.foldr derive norm norm
  in st { normState = newNorm }
  where
    derive :: IndexedGen -> Norm -> Norm
    derive (IndexedGen c1 t1 g1) acc =
      -- Only consider non-overridden generators as potential overriders
      case g1 of
        Overridden _ -> acc  -- Overridden norms cannot override others
        _ -> S.foldr
               (\(IndexedGen c2 t2 g2) a ->
                  -- Check if g1 can override g2:
                  -- 1. c1 dominates c2 (hierarchy check)
                  -- 2. g1 and g2 conflict (semantic check)
                  -- 3. t1 >= t2 (temporal check: later or equal time)
                  -- 4. g2 is not already overridden
                  case g2 of
                    Overridden _ -> a  -- Don't override already overridden norms
                    _ -> if dominates c1 c2 && conflicts g1 g2 && t1 >= t2
                            then let newGen = IndexedGen c2 t2 (Overridden g2)
                                 in if S.member newGen a
                                       then a
                                       else S.insert newGen a
                            else a)
               acc
               acc

--------------------------------------------------
-- RULE SET
--------------------------------------------------

rules :: [Rule]
rules =
  [ normRuleWrapper objectClaimToDelivery
  , normRuleWrapper claimFulfilled
  , normRuleWrapper claimEnforceable
  , normRuleWrapper obligationViolation
  , normToPatrimony
  , patrimonyToNorm
  , legislationRule
  , statuteCreatesObligation
  , overrideRule
  ]

--------------------------------------------------
-- SAMPLE EXECUTION
--------------------------------------------------

runExample :: SystemState -> SystemState
runExample =
  runSystem rules

-- Legacy function for backward compatibility
runExampleNorm :: Norm -> Norm
runExampleNorm norm =
  let initialState = SystemState { normState = norm, patrState = P.emptyPatrimony }
      finalState = runExample initialState
  in normState finalState