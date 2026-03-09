{-# LANGUAGE GADTs #-}

-- | Quantale interpretation of the normative system.
--
-- This module is INTERPRETATIVE rather than OPERATIONAL: the runtime rule engine
-- does not depend on it. The quantale describes the algebraic structure that
-- emerges from the system. See docs/quantale_interpretation.md for the full
-- formalization.
--
-- Carrier: G = all IndexedGen, Q = 𝒫(G). Runtime Norm = finite elements of Q.
-- Join = union. Multiplication = Kleisli lift of partial composition to sets.
-- Rule fixpoint (Logic.runSystem) and Kleene star operate over different structures.
module Quantale where

import Capability (capabilitySupremum)
import FixedPoint (fixpoint)
import LegalOntology (Act(..), composeActs)
import NormativeGenerators
import Data.Time.Calendar (fromGregorian)
import qualified Data.Set as S

-- | Partial composition of generators. Succeeds only for GAct pairs (Simple/Simple,
-- Counter/Counter, or with Id). Models temporal sequencing of actions.
-- Lifted to sets by mulNorm (Kleisli lifting).
composeGen :: Generator -> Generator -> Maybe Generator
composeGen (GAct Id) (GAct b) = Just (GAct b)
composeGen (GAct a) (GAct Id) = Just (GAct a)
composeGen (GAct a@Simple{}) (GAct b@Simple{}) = Just (GAct (composeActs a b))
composeGen (GAct a@Counter{}) (GAct b@Counter{}) = Just (GAct (composeActs a b))
composeGen _ _ = Nothing

-- | Indexed multiplication: composes two IndexedGen, combining capability
-- (supremum) and time (max). Partial—returns Nothing when composeGen fails.
mulIndexed :: IndexedGen -> IndexedGen -> Maybe IndexedGen
mulIndexed (IndexedGen cap1 t1 g1) (IndexedGen cap2 t2 g2) =
  case composeGen g1 g2 of
    Just g' ->
      let cap' = capabilitySupremum cap1 cap2
          t' = max t1 t2
      in Just (IndexedGen cap' t' g')
    Nothing -> Nothing

-- | Quantale multiplication: Kleisli lifting of partial composition to sets.
-- a · b = { x · y | x ∈ a, y ∈ b, composition defined }.
-- Models temporal composition of acts; non-act generators are inert.
mulNorm :: Norm -> Norm -> Norm
mulNorm a b =
  S.fromList
    [ g
    | x <- S.toList a
    , y <- S.toList b
    , Just g <- [mulIndexed x y]
    ]

-- | Quantale join: set union. Corresponds to ∨ in the lattice (Q, ⊆).
joinNorm :: Norm -> Norm -> Norm
joinNorm = S.union

-- | Quantale unit: singleton {GAct Id}. Identity for multiplication within
-- the act subalgebra. mulNorm unitNorm x = x when x contains composable acts.
unitNorm :: Norm
unitNorm =
  S.singleton (IndexedGen BaseAuthority (fromGregorian 1 1 1) (GAct Id))

-- | Kleene star: closure under multiplication. x* = 1 ∨ x ∨ x² ∨ x³ ∨ ...
-- Monoidal layer—NOT used by the rule engine. Rule fixpoint (Logic.runSystem)
-- is the order-theoretic closure; this is the algebraic closure over acts.
kleeneStar :: Norm -> Norm
kleeneStar x =
  fixpoint step (joinNorm unitNorm x)
  where
    step acc = joinNorm acc (mulNorm acc x)

