{-# LANGUAGE LambdaCase #-}

module Runtime.Intrinsics
  ( IntrinsicEnv
  , IntrinsicValue
  , defaultIntrinsicEnv
  , evaluateIntrinsic
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Time.Calendar (Day, diffDays)

-- | Value passed to intrinsics: Double for numeric, Day for dates.
type IntrinsicValue = Either Double Day

-- | Intrinsic functions are pure predicates: [IntrinsicValue] -> Bool.
type IntrinsicFn = [IntrinsicValue] -> Bool

type IntrinsicEnv = Map String IntrinsicFn

-- | Default whitelist of allowed intrinsics.
-- All are pure, deterministic, side-effect free.
defaultIntrinsicEnv :: IntrinsicEnv
defaultIntrinsicEnv =
  M.fromList
    [ ("aboveThreshold", aboveThreshold)
    , ("belowThreshold", belowThreshold)
    , ("between", between)
    , ("daysBetween", daysBetween)
    , ("withinWindow", withinWindow)
    , ("percentage", percentage)
    , ("taxAmount", taxAmount)
    ]

aboveThreshold :: IntrinsicFn
aboveThreshold = \case
  [Left v, Left t] -> v > t
  _ -> False

belowThreshold :: IntrinsicFn
belowThreshold = \case
  [Left v, Left t] -> v < t
  _ -> False

between :: IntrinsicFn
between = \case
  [Left v, Left lo, Left hi] -> v >= lo && v <= hi
  _ -> False

-- daysBetween: for condition use, check if days between dates is <= N.
-- Simplified: daysBetweenLEQ(d1, d2, maxDays) -> abs(diff) <= maxDays
-- For now we implement daysBetween(d1,d2) as d2 >= d1 (date order check)
daysBetween :: IntrinsicFn
daysBetween = \case
  [Right d1, Right d2] -> d2 >= d1
  _ -> False

-- withinWindow: date >= start && date <= end
withinWindow :: IntrinsicFn
withinWindow = \case
  [Right d, Right start, Right end] -> d >= start && d <= end
  _ -> False

-- percentage/taxAmount: for condition use, these might check a computed value.
-- Placeholder: accept two numeric args and return True (always passes)
percentage :: IntrinsicFn
percentage = \case
  [Left _amount, Left _rate] -> True
  _ -> False

taxAmount :: IntrinsicFn
taxAmount = \case
  [Left _base, Left _rate] -> True
  _ -> False

-- | Evaluate an intrinsic by name with resolved arguments.
evaluateIntrinsic :: IntrinsicEnv -> String -> [IntrinsicValue] -> Maybe Bool
evaluateIntrinsic env name args = do
  fn <- M.lookup name env
  pure (fn args)
