module Runtime.Provenance
  ( AuditClassification(..)
  , ComplianceSummary(..)
  , DerivationStep(..)
  , FactRef(..)
  , RuleFire(..)
  , RuleOrigin(..)
  , ScenarioSeed(..)
  , Verdict(..)
  ) where

import Data.Time.Calendar (Day)
import NormativeGenerators (IndexedGen)
import qualified Patrimony as P

data FactRef
  = NormFact IndexedGen
  | PatrFact P.PatrimonyGen
  deriving (Eq, Ord, Show)

data RuleOrigin
  = DslRule String
  | BuiltInRule String
  deriving (Eq, Ord, Show)

data ScenarioSeed = ScenarioSeed
  { seedDay :: Day
  , seedText :: String
  , seedFacts :: [FactRef]
  }
  deriving (Eq, Show)

data RuleFire = RuleFire
  { ruleOrigin :: RuleOrigin
  , witnessDay :: Day
  , witnessFacts :: [FactRef]
  , consequent :: IndexedGen
  , insertedNew :: Bool
  }
  deriving (Eq, Show)

data DerivationStep
  = SeedStep ScenarioSeed
  | RuleStep RuleFire
  deriving (Eq, Show)

data Verdict
  = Compliant
  | NonCompliant
  deriving (Eq, Show)

data AuditClassification = AuditClassification
  { classificationAuthority :: String
  , classificationFiber :: String
  }
  deriving (Eq, Show)

data ComplianceSummary = ComplianceSummary
  { complianceVerdict :: Verdict
  , violatedNorms :: [IndexedGen]
  , fulfilledNorms :: [IndexedGen]
  , enforceableNorms :: [IndexedGen]
  , pendingObligations :: [IndexedGen]
  , activeProhibitions :: [IndexedGen]
  , classifications :: [AuditClassification]
  }
  deriving (Eq, Show)
