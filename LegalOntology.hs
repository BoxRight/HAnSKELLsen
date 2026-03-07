{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}

module LegalOntology where

import Data.Time.Calendar (Day)
import qualified Data.Set as S


--------------------------------------------------
-- PERSONS
--------------------------------------------------

data PSubtype
  = Legal
  | Physical
  deriving (Eq, Ord, Show)

data Capacity
  = Enjoy
  | Exercise
  deriving (Eq, Ord, Show)

data Person = Person
  { pSubtype   :: PSubtype
  , pName      :: String
  , pCapacity  :: Capacity
  , pAddress   :: String
  }
  deriving (Eq, Ord, Show)


--------------------------------------------------
-- OBJECTS
--------------------------------------------------

data Thing
  = Movable
  | NonMovable
  | Expendable
  deriving (Eq, Ord, Show)

data Service
  = Performance (Maybe Object)
  | Omission    (Maybe Object)
  deriving (Eq, Ord, Show)

data OSubtype
  = ThingSubtype Thing
  | ServiceSubtype Service
  deriving (Eq, Ord, Show)

data Object = Object
  { oSubtype :: OSubtype
  , oName    :: String
  , oStart   :: Day
  , oDue     :: Day
  , oEnd     :: Maybe Day
  }
  deriving (Eq, Ord, Show)


--------------------------------------------------
-- ACTS
--------------------------------------------------

data Active
data Passive

data Act r where

  Id
    :: Act r

  Simple
    :: Person
    -> Object
    -> Person
    -> Act Active

  Counter
    :: Person
    -> Object
    -> Person
    -> Act Passive

  Seq
    :: [Act r]
    -> Act r

  Par
    :: S.Set (Act r)
    -> Act r

deriving instance Eq   (Act r)
deriving instance Ord  (Act r)
deriving instance Show (Act r)

flattenSeq :: [Act r] -> [Act r]
flattenSeq (Seq xs : ys) = flattenSeq (xs ++ ys)
flattenSeq (x : xs)      = x : flattenSeq xs
flattenSeq []            = []

flattenPar :: S.Set (Act r) -> S.Set (Act r)
flattenPar xs =
  S.foldr
    (\act acc ->
      case act of
        Par ys -> S.union (flattenPar ys) acc
        _ -> S.insert act acc
    )
    S.empty
    xs

normalizeAct :: Act r -> Act r
normalizeAct act =
  case act of
    Id -> Id
    Simple p o t -> Simple p o t
    Counter p o t -> Counter p o t
    Seq xs ->
      let flattened = flattenSeq (map normalizeAct xs)
          withoutId = filter (/= Id) flattened
      in case withoutId of
          [] -> Id
          [x] -> x
          ys -> Seq ys
    Par xs ->
      let flattened = flattenPar (S.map normalizeAct xs)
          withoutId = S.delete Id flattened
      in Par withoutId

composeActs :: Act r -> Act r -> Act r
composeActs a b = normalizeAct (Seq [a, b])


--------------------------------------------------
-- LEGAL FACTS
--------------------------------------------------

data LegalEvent
  = NaturalFact String
  | HumanAct    String
  deriving (Eq, Ord, Show)


--------------------------------------------------
-- NORMATIVE MODALITIES
--------------------------------------------------

data Claim r where
  Claim :: Act r -> Claim r

deriving instance Eq   (Claim r)
deriving instance Ord  (Claim r)
deriving instance Show (Claim r)


data Obligation r where
  Obligation :: Act r -> Obligation r

deriving instance Eq   (Obligation r)
deriving instance Ord  (Obligation r)
deriving instance Show (Obligation r)


data Prohibition r where
  Prohibition :: Act r -> Prohibition r

deriving instance Eq   (Prohibition r)
deriving instance Ord  (Prohibition r)
deriving instance Show (Prohibition r)


data Privilege r where
  Privilege :: Act r -> Privilege r

deriving instance Eq   (Privilege r)
deriving instance Ord  (Privilege r)
deriving instance Show (Privilege r)


--------------------------------------------------
-- PATRIMONY
--------------------------------------------------

data PatrimonyItem
  = AssetClaim   (Claim Active)
  | Liability    (Obligation Active)
  | OwnedObject  Object
  deriving (Eq, Ord, Show)

data Patrimony = Patrimony
  { assets      :: S.Set PatrimonyItem
  }
  deriving (Eq, Ord, Show)