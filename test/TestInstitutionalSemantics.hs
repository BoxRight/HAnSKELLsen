{-# LANGUAGE GADTs #-}

module TestInstitutionalSemantics
  ( institutionalSemanticsTests
  ) where

import Data.Time.Calendar (Day, fromGregorian)
import LegalOntology
import Logic (runExample, SystemState(..))
import NormativeGenerators (CapabilityIndex(..), activeNorms, IndexedGen(..), Generator(..))
import qualified Patrimony as P
import qualified Data.Set as S
import Test.Tasty (testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)

institutionalSemanticsTests =
  testGroup
    "Institutional modeling semantics"
    [ testCase "authority override: legislative privilege overrides private prohibition" testAuthorityOverride
    , testCase "nested override: higher authority wins" testNestedOverride
    , testCase "overridden norms excluded from activeNorms" testActiveNormsExcludesOverridden
    ]

baseDate :: Day
baseDate = fromGregorian 2025 1 1

mkPerson :: String -> Person
mkPerson name = Person Legal name Exercise "addr"

mkThing :: String -> Object
mkThing name =
  Object
    (ThingSubtype Movable)
    name
    baseDate
    baseDate
    Nothing

-- Private prohibition vs legislative privilege: legislative should override
testAuthorityOverride :: IO ()
testAuthorityOverride = do
  let alice = mkPerson "Alice"
      bob = mkPerson "Bob"
      obj = mkThing "Thing"
      prohibition = Prohibition (Simple alice obj bob)
      privilege = Privilege (Counter bob obj alice)
      privateProhib = IndexedGen PrivatePower baseDate (GProhibition prohibition)
      legislativePriv = IndexedGen LegislativePower baseDate (GPrivilege privilege)
      initialState =
        SystemState
          { normState = S.fromList [privateProhib, legislativePriv]
          , patrState = P.emptyPatrimony
          }
      finalState = runExample initialState
      active = activeNorms (normState finalState)
      -- Legislative privilege conflicts with private prohibition; legislative dominates.
      -- Override rule should add Overridden(prohibition).
      -- activeNorms filters out Overridden, so we should have legislative privilege
      -- but the private prohibition's IndexedGen is still in normState (not removed).
      -- The Overridden marker is a separate IndexedGen.
      hasOverriddenMarker =
        any
          (\(IndexedGen _ _ g) ->
             case g of
               Overridden _ -> True
               _ -> False)
          (S.toList (normState finalState))
  assertBool "override rule should add Overridden marker" hasOverriddenMarker
  -- activeNorms should include the legislative privilege (not overridden)
  assertBool
    "active norms should include legislative privilege"
    (any
       (\(IndexedGen _ _ g) ->
          case g of
            GPrivilege _ -> True
            _ -> False)
       (S.toList active))

-- Constitutional > Legislative > Private. Higher authority overrides lower.
testNestedOverride :: IO ()
testNestedOverride = do
  let alice = mkPerson "Alice"
      bob = mkPerson "Bob"
      obj = mkThing "Thing"
      prohibition = Prohibition (Simple alice obj bob)
      privilege = Privilege (Counter bob obj alice)
      privateProhib = IndexedGen PrivatePower baseDate (GProhibition prohibition)
      legislativePriv = IndexedGen LegislativePower baseDate (GPrivilege privilege)
      constitutionalPriv = IndexedGen ConstitutionalPower baseDate (GPrivilege privilege)
      initialState =
        SystemState
          { normState = S.fromList [privateProhib, legislativePriv, constitutionalPriv]
          , patrState = P.emptyPatrimony
          }
      finalState = runExample initialState
      -- Both legislative and constitutional conflict with private prohibition.
      -- Constitutional dominates both; the override rule should mark the prohibition as overridden.
      hasOverridden =
        any
          (\(IndexedGen _ _ g) ->
             case g of
               Overridden (GProhibition _) -> True
               _ -> False)
          (S.toList (normState finalState))
  assertBool "prohibition should be overridden by higher authority" hasOverridden

-- activeNorms filters out generators wrapped in Overridden
testActiveNormsExcludesOverridden :: IO ()
testActiveNormsExcludesOverridden = do
  let alice = mkPerson "Alice"
      bob = mkPerson "Bob"
      obj = mkThing "Thing"
      prohibition = Prohibition (Simple alice obj bob)
      privilege = Privilege (Counter bob obj alice)
      privateProhib = IndexedGen PrivatePower baseDate (GProhibition prohibition)
      legislativePriv = IndexedGen LegislativePower baseDate (GPrivilege privilege)
      overriddenProhib = IndexedGen PrivatePower baseDate (Overridden (GProhibition prohibition))
      norm = S.fromList [privateProhib, legislativePriv, overriddenProhib]
      active = activeNorms norm
      -- activeNorms should exclude overriddenProhib (its gen is Overridden _)
      activeGens = map (\(IndexedGen _ _ g) -> g) (S.toList active)
  assertBool
    "activeNorms should not include Overridden generators"
    (not (any (\g -> case g of Overridden _ -> True; _ -> False) activeGens))
