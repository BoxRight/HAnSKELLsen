{-# LANGUAGE GADTs #-}

module Quantale where

import Capability (capabilitySupremum)
import FixedPoint (fixpoint)
import LegalOntology (Act(..), composeActs)
import NormativeGenerators
import Data.Time.Calendar (fromGregorian)
import qualified Data.Set as S

composeGen :: Generator -> Generator -> Maybe Generator
composeGen (GAct Id) (GAct b) = Just (GAct b)
composeGen (GAct a) (GAct Id) = Just (GAct a)
composeGen (GAct a@Simple{}) (GAct b@Simple{}) = Just (GAct (composeActs a b))
composeGen (GAct a@Counter{}) (GAct b@Counter{}) = Just (GAct (composeActs a b))
composeGen _ _ = Nothing

mulIndexed :: IndexedGen -> IndexedGen -> Maybe IndexedGen
mulIndexed (IndexedGen cap1 t1 g1) (IndexedGen cap2 t2 g2) =
  case composeGen g1 g2 of
    Just g' ->
      let cap' = capabilitySupremum cap1 cap2
          t' = max t1 t2
      in Just (IndexedGen cap' t' g')
    Nothing -> Nothing

mulNorm :: Norm -> Norm -> Norm
mulNorm a b =
  S.fromList
    [ g
    | x <- S.toList a
    , y <- S.toList b
    , Just g <- [mulIndexed x y]
    ]

joinNorm :: Norm -> Norm -> Norm
joinNorm = S.union

unitNorm :: Norm
unitNorm =
  S.singleton (IndexedGen BaseAuthority (fromGregorian 1 1 1) (GAct Id))

kleeneStar :: Norm -> Norm
kleeneStar x =
  fixpoint step (joinNorm unitNorm x)
  where
    step acc = joinNorm acc (mulNorm acc x)

