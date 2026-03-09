{-# LANGUAGE GADTs #-}

module TestInvariants
  ( invariantTests
  ) where

import Data.Time.Calendar (fromGregorian)
import LegalOntology
import Logic (runExample, SystemState(..))
import NormativeGenerators
import qualified Patrimony as P
import qualified Data.Set as S
import Test.Tasty (testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)

invariantTests =
  testGroup
    "Fixpoint kernel invariants"
    [ testCase "fixpoint idempotency (logic.hs regression)" testFixpointIdempotency
    , testCase "monotonicity (logic.hs regression)" testMonotonicity
    , testCase "fixpoint idempotency property" testFixpointIdempotencyProperty
    , testCase "monotonicity property" testMonotonicityProperty
    ]

-- Build the same initial state as logic.hs
mkInitialState :: SystemState
mkInitialState =
  let legalPerson = Person Legal "Alice Corp" Exercise "123 Business St"
      physicalPerson = Person Physical "Bob" Enjoy "456 Home Ave"
      movableThing =
        Object
          (ThingSubtype Movable)
          "Car"
          (fromGregorian 2025 3 1)
          (fromGregorian 2025 3 10)
          Nothing
      serviceObject =
        Object
          (ServiceSubtype (Performance Nothing))
          "Delivery Service"
          (fromGregorian 2025 3 1)
          (fromGregorian 2025 3 10)
          Nothing
      claim = Claim (Simple legalPerson movableThing physicalPerson)
      testDate = fromGregorian 2025 3 1
      thingClaim =
        IndexedGen
          PrivatePower
          testDate
          (GClaim (Claim (Simple legalPerson movableThing physicalPerson)))
      initialNorm = S.fromList [thingClaim]
  in SystemState
       { normState = initialNorm
       , patrState = S.fromList [P.Capability "legislative_power", P.Capability "private_power"]
       }

testFixpointIdempotency :: IO ()
testFixpointIdempotency = do
  let initialState = mkInitialState
      derivedState = runExample initialState
      fixpointState2 = runExample derivedState
  assertBool "fixpoint should be idempotent" (fixpointState2 == derivedState)

testMonotonicity :: IO ()
testMonotonicity = do
  let initialState = mkInitialState
      derivedState = runExample initialState
  assertBool
    "normState should be monotonic (initial ⊆ final)"
    (normState initialState `S.isSubsetOf` normState derivedState)
  assertBool
    "patrState should be monotonic (initial ⊆ final)"
    (patrState initialState `S.isSubsetOf` patrState derivedState)

-- Property: for any state, running the fixpoint twice yields the same result
testFixpointIdempotencyProperty :: IO ()
testFixpointIdempotencyProperty = do
  let emptyState =
        SystemState {normState = S.empty, patrState = P.emptyPatrimony}
      state1 = runExample emptyState
      state2 = runExample (mkInitialState)
  assertBool "empty state fixpoint idempotent" (runExample state1 == state1)
  assertBool "initial state fixpoint idempotent" (runExample state2 == state2)

-- Property: runSystem rules s produces state where initial ⊆ final
testMonotonicityProperty :: IO ()
testMonotonicityProperty = do
  let emptyState =
        SystemState {normState = S.empty, patrState = P.emptyPatrimony}
      derivedEmpty = runExample emptyState
      derivedInitial = runExample mkInitialState
  assertBool
    "empty: normState monotonic"
    (normState emptyState `S.isSubsetOf` normState derivedEmpty)
  assertBool
    "empty: patrState monotonic"
    (patrState emptyState `S.isSubsetOf` patrState derivedEmpty)
  assertBool
    "initial: normState monotonic"
    (normState mkInitialState `S.isSubsetOf` normState derivedInitial)
  assertBool
    "initial: patrState monotonic"
    (patrState mkInitialState `S.isSubsetOf` patrState derivedInitial)
