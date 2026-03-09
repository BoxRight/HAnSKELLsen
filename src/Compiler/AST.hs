module Compiler.AST where

import Data.Time.Calendar (Day)
import NormativeGenerators (CapabilityIndex)

data PartySubtypeAst
  = NaturalPartyAst
  | LegalPartyAst
  deriving (Eq, Ord, Show)

data PartyCapacityAst
  = EnjoyCapacityAst
  | ExerciseCapacityAst
  deriving (Eq, Ord, Show)

data LawMetaAst = LawMetaAst
  { lawNameAst :: String
  , lawAuthorityAst :: CapabilityIndex
  , lawEnactedAst :: Day
  }
  deriving (Eq, Show)

data PartyDecl = PartyDecl
  { partyAlias :: String
  , partyDisplayName :: String
  , partySubtypeAst :: PartySubtypeAst
  , partyCapacityAst :: PartyCapacityAst
  , partyAddressAst :: Maybe String
  }
  deriving (Eq, Show)

data ObjectKindAst
  = MovableKind
  | NonMovableKind
  | ExpendableKind
  | MoneyKind
  | ServiceKind
  deriving (Eq, Ord, Show)

data ServiceModeAst
  = PerformanceServiceAst
  | OmissionServiceAst
  deriving (Eq, Ord, Show)

data ObjectDecl = ObjectDecl
  { objectAlias :: String
  , objectKind :: ObjectKindAst
  , objectServiceMode :: Maybe ServiceModeAst
  , objectRelatedObject :: Maybe String
  , objectStartAst :: Maybe Day
  , objectDueAst :: Maybe Day
  , objectEndAst :: Maybe Day
  }
  deriving (Eq, Show)

data VocabularyDecl
  = VerbVocabulary
      { vocabularySurface :: String
      , vocabularyCanonical :: String
      }
  | ObjectVocabulary
      { vocabularySurface :: String
      , vocabularyCanonical :: String
      }
  deriving (Eq, Show)

data ActionPolarityAst
  = PositiveActionAst
  | NegativeActionAst
  deriving (Eq, Ord, Show)

data ActionPhraseAst = ActionPhraseAst
  { actionActorName :: String
  , actionVerb :: String
  , actionObjectName :: String
  , actionTargetName :: Maybe String
  , actionPolarity :: ActionPolarityAst
  }
  deriving (Eq, Show)

data ClaimPhraseAst = ClaimPhraseAst
  { claimHolderName :: String
  , claimVerb :: String
  , claimObjectName :: String
  , claimAgainstName :: String
  }
  deriving (Eq, Show)

data ModalityAst
  = ObligationAst ActionPhraseAst
  | ClaimAst ClaimPhraseAst
  | ProhibitionAst ActionPhraseAst
  | PrivilegeAst ActionPhraseAst
  deriving (Eq, Show)

data ProcedureAst = ProcedureAst
  { procedureName :: String
  , procedureBranches :: [[ActionPhraseAst]]
  }
  deriving (Eq, Show)

data StandingFactAst
  = OwnershipFactAst
      { factPartyName :: String
      , factObjectName :: String
      }
  | CapabilityFactAst
      { factCapability :: CapabilityIndex
      }
  | AssetFactAst
      { factAssetName :: String
      }
  | LiabilityFactAst
      { factLiabilityName :: String
      }
  deriving (Eq, Show)

data ConditionAst
  = InstitutionalConditionAst StandingFactAst
  | ActionConditionAst ActionPhraseAst
  deriving (Eq, Show)

data RuleAst = RuleAst
  { ruleNameAst :: String
  , ruleConditionAst :: ConditionAst
  , ruleConsequentAst :: ModalityAst
  }
  deriving (Eq, Show)

data ClauseAst
  = ClauseModality ModalityAst
  | ClauseProcedure ProcedureAst
  | ClauseRule RuleAst
  | ClauseStandingFact StandingFactAst
  deriving (Eq, Show)

data ArticleAst = ArticleAst
  { articleNumber :: Int
  , articleHeading :: Maybe String
  , articleClauses :: [ClauseAst]
  }
  deriving (Eq, Show)

data LegalEventAst
  = HumanEventAst String
  | NaturalEventAst String
  deriving (Eq, Show)

data ScenarioAssertionAst
  = ScenarioAct ActionPhraseAst
  | ScenarioCounterAct ActionPhraseAst
  | ScenarioCondition ConditionAst
  | ScenarioEvent LegalEventAst
  deriving (Eq, Show)

data ScenarioEntryAst = ScenarioEntryAst
  { scenarioDate :: Day
  , scenarioAssertions :: [ScenarioAssertionAst]
  }
  deriving (Eq, Show)

data ScenarioAst = ScenarioAst
  { scenarioName :: String
  , scenarioEntries :: [ScenarioEntryAst]
  }
  deriving (Eq, Show)

data LawModuleAst = LawModuleAst
  { lawMeta :: LawMetaAst
  , lawParties :: [PartyDecl]
  , lawObjects :: [ObjectDecl]
  , lawVocabulary :: [VocabularyDecl]
  , lawArticles :: [ArticleAst]
  , lawScenarios :: [ScenarioAst]
  }
  deriving (Eq, Show)
