{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}

module NormativeGenerators where

import LegalOntology
import Data.Time.Calendar (Day)
import qualified Data.Set as S


--------------------------------------------------
-- GENERATORS
--------------------------------------------------

data Generator where

  GAct
    :: Act r
    -> Generator

  GClaim
    :: Claim r
    -> Generator

  GObligation
    :: Obligation r
    -> Generator

  GProhibition
    :: Prohibition r
    -> Generator

  GPrivilege
    :: Privilege r
    -> Generator

  GEvent
    :: LegalEvent
    -> Generator

  GFulfillment
    :: Act Active
    -> Generator

  GViolation
    :: Act Passive
    -> Generator

  GEnforceable
    :: Act Active
    -> Generator

  GStatute
    :: Act Active
    -> Generator

  Overridden
    :: Generator
    -> Generator

instance Eq Generator where
  a == b = show a == show b

instance Ord Generator where
  compare a b = compare (show a) (show b)

instance Show Generator where
  show (GAct a)        = "Act:" ++ show a
  show (GClaim c)      = "Claim:" ++ show c
  show (GObligation o) = "Oblig:" ++ show o
  show (GProhibition p)= "Prohib:" ++ show p
  show (GPrivilege p)  = "Priv:" ++ show p
  show (GEvent e)      = "Event:" ++ show e
  show (GFulfillment a) = "Fulfillment:" ++ show a
  show (GViolation a)   = "Violation:" ++ show a
  show (GEnforceable a) = "Enforceable:" ++ show a
  show (GStatute a)     = "Statute:" ++ show a
  show (Overridden g)   = "Overridden(" ++ show g ++ ")"


--------------------------------------------------
-- STAGE 5: CAPABILITY INDEXING
--------------------------------------------------

data CapabilityIndex
  = PrivatePower
  | LegislativePower
  | JudicialPower
  | AdministrativePower
  | ConstitutionalPower
  deriving (Eq, Ord, Show)

-- Indexed generator: pairs capability index, time, and generator
data IndexedGen = IndexedGen
  { capIndex :: CapabilityIndex
  , time     :: Day
  , gen      :: Generator
  }
  deriving (Eq, Ord, Show)

--------------------------------------------------
-- NORMATIVE STATE
--------------------------------------------------

-- Norm is now a set of indexed generators
type Norm = S.Set IndexedGen


--------------------------------------------------
-- BASIC OPERATIONS
--------------------------------------------------

emptyNorm :: Norm
emptyNorm = S.empty


insertGen :: IndexedGen -> Norm -> Norm
insertGen = S.insert


memberGen :: IndexedGen -> Norm -> Bool
memberGen = S.member


unionNorm :: Norm -> Norm -> Norm
unionNorm = S.union

-- Helper to create indexed generator with default (PrivatePower) index and time
-- For backward compatibility during migration
indexedGen :: CapabilityIndex -> Day -> Generator -> IndexedGen
indexedGen capIdx t = IndexedGen capIdx t

-- Default to PrivatePower and a default date for unindexed generators
defaultIndexed :: Day -> Generator -> IndexedGen
defaultIndexed t g = IndexedGen PrivatePower t g

-- Temporal filtering: get norms valid at a given time
validAt :: Day -> IndexedGen -> Bool
validAt t g = time g <= t

-- Filter norm to only include generators valid at given time
normAt :: Day -> Norm -> Norm
normAt t = S.filter (validAt t)

-- Check if a generator is overridden
isOverridden :: Generator -> Bool
isOverridden (Overridden _) = True
isOverridden _ = False

-- Filter norm to exclude overridden generators (for active normative queries)
activeNorms :: Norm -> Norm
activeNorms = S.filter (\(IndexedGen _ _ g) -> not (isOverridden g))


--------------------------------------------------
-- LIFTING HELPERS
--------------------------------------------------

actGen :: Act r -> Generator
actGen = GAct


claimGen :: Claim r -> Generator
claimGen = GClaim


obligGen :: Obligation r -> Generator
obligGen = GObligation


prohibGen :: Prohibition r -> Generator
prohibGen = GProhibition


privGen :: Privilege r -> Generator
privGen = GPrivilege


eventGen :: LegalEvent -> Generator
eventGen = GEvent