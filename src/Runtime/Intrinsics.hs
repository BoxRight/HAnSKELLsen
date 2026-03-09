{-# LANGUAGE LambdaCase #-}

module Runtime.Intrinsics
  ( IntrinsicEnv
  , IntrinsicValue(..)
  , defaultIntrinsicEnv
  , evaluateIntrinsic
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Time.Calendar (Day, diffDays)

-- | Value passed to intrinsics: numeric or date.
data IntrinsicValue
  = NumericValue Double
  | DateValue Day
  deriving (Eq, Show)

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
  [NumericValue v, NumericValue t] -> v > t
  _ -> False

belowThreshold :: IntrinsicFn
belowThreshold = \case
  [NumericValue v, NumericValue t] -> v < t
  _ -> False

between :: IntrinsicFn
between = \case
  [NumericValue v, NumericValue lo, NumericValue hi] -> v >= lo && v <= hi
  _ -> False

-- daysBetween: two signatures:
-- (d1, d2) -> Bool: d2 >= d1 (backward compatible, date order)
-- (d1, d2, maxDays) -> Bool: abs(diffDays d2 d1) <= maxDays (filing window)
daysBetween :: IntrinsicFn
daysBetween = \case
  [DateValue d1, DateValue d2] -> d2 >= d1
  [DateValue d1, DateValue d2, NumericValue maxDays] ->
    abs (fromIntegral (diffDays d2 d1)) <= maxDays
  _ -> False

-- withinWindow: date >= start && date <= end
withinWindow :: IntrinsicFn
withinWindow = \case
  [DateValue d, DateValue start, DateValue end] -> d >= start && d <= end
  _ -> False

-- percentage/taxAmount: for condition use, these might check a computed value.
-- Placeholder: accept two numeric args and return True (always passes)
percentage :: IntrinsicFn
percentage = \case
  [NumericValue _amount, NumericValue _rate] -> True
  _ -> False

taxAmount :: IntrinsicFn
taxAmount = \case
  [NumericValue _base, NumericValue _rate] -> True
  _ -> False

-- | Evaluate an intrinsic by name with resolved arguments.
evaluateIntrinsic :: IntrinsicEnv -> String -> [IntrinsicValue] -> Maybe Bool
evaluateIntrinsic env name args = do
  fn <- M.lookup name env
  pure (fn args)
