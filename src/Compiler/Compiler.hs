module Compiler.Compiler
  ( CompiledLawModule(..)
  , ProcedureIR(..)
  , ResolvedAction(..)
  , ResolvedClaim(..)
  , ResolvedCondition(..)
  , RuleSpec(..)
  , compileInitialNorm
  , compileInitialSystemState
  , compileLawModule
  ) where

import Compiler.AST
import Compiler.SymbolTable
import Data.Either (partitionEithers)
import Data.Maybe (mapMaybe)
import qualified Data.Set as S
import Data.Time.Calendar (Day, fromGregorian)
import LegalOntology
import Logic (SystemState(..))
import qualified Patrimony as P
import NormativeGenerators

data ResolvedAction = ResolvedAction
  { resolvedActionVerb :: String
  , resolvedActionActor :: Person
  , resolvedActionObject :: Object
  , resolvedActionTarget :: Person
  }
  deriving (Eq, Show)

data ResolvedClaim = ResolvedClaim
  { resolvedClaimVerb :: String
  , resolvedClaimHolder :: Person
  , resolvedClaimAgainst :: Person
  , resolvedClaimObject :: Object
  }
  deriving (Eq, Show)

data ResolvedCondition
  = ResolvedOwnershipCondition Person Object
  deriving (Eq, Show)

data ProcedureIR = ProcedureIR
  { procedureIrName :: String
  , procedureIrBranches :: [Act Active]
  }
  deriving (Eq, Show)

data RuleSpec = RuleSpec
  { ruleSpecName :: String
  , ruleSpecCondition :: ResolvedCondition
  , ruleSpecConsequent :: IndexedGen
  }
  deriving (Eq, Show)

data CompiledLawModule = CompiledLawModule
  { compiledMetadata :: LawMetaAst
  , compiledFacts :: [IndexedGen]
  , compiledProcedures :: [ProcedureIR]
  , compiledRules :: [RuleSpec]
  }
  deriving (Eq, Show)

compileLawModule :: LawModuleAst -> Either [Diagnostic] CompiledLawModule
compileLawModule lawModule = do
  symbols <- buildSymbolTable lawModule
  let meta = lawMeta lawModule
      clauses = concatMap articleClauses (lawArticles lawModule)
      results = map (compileClause meta symbols) clauses
      diagnostics = gatherErrors results
      payloads = gatherValues results
  case diagnostics of
    [] ->
      Right $
        CompiledLawModule
          { compiledMetadata = meta
          , compiledFacts = mapMaybe extractFact payloads
          , compiledProcedures = mapMaybe extractProcedure payloads
          , compiledRules = mapMaybe extractRule payloads
          }
    errs -> Left errs

compileInitialNorm :: LawModuleAst -> Either [Diagnostic] Norm
compileInitialNorm lawModule = do
  compiled <- compileLawModule lawModule
  pure (S.fromList (compiledFacts compiled))

compileInitialSystemState :: LawModuleAst -> Either [Diagnostic] SystemState
compileInitialSystemState lawModule = do
  norm <- compileInitialNorm lawModule
  pure $
    SystemState
      { normState = norm
      , patrState = P.emptyPatrimony
      }

data ClauseResult
  = CompiledFact IndexedGen
  | CompiledProcedure ProcedureIR
  | CompiledRule RuleSpec

compileClause
  :: LawMetaAst
  -> SymbolTable
  -> ClauseAst
  -> Either [Diagnostic] ClauseResult
compileClause meta symbols clause =
  case clause of
    ClauseModality modality ->
      CompiledFact <$> compileModality meta symbols modality
    ClauseProcedure procedure ->
      CompiledProcedure <$> compileProcedure symbols procedure
    ClauseRule ruleAst ->
      CompiledRule <$> compileRuleSpec meta symbols ruleAst

compileModality
  :: LawMetaAst
  -> SymbolTable
  -> ModalityAst
  -> Either [Diagnostic] IndexedGen
compileModality meta symbols modality =
  indexedGen (lawAuthorityAst meta) (lawEnactedAst meta)
    <$> case modality of
          ObligationAst action ->
            GObligation . Obligation . resolvedActionToAct
              <$> resolveAction symbols action
          ClaimAst claimAst ->
            GClaim . Claim . resolvedClaimToAct
              <$> resolveClaim symbols claimAst
          ProhibitionAst action ->
            GProhibition . Prohibition . resolvedActionToAct
              <$> resolveAction symbols action
          PrivilegeAst action ->
            GPrivilege . Privilege . resolvedActionToAct
              <$> resolveAction symbols action

compileProcedure
  :: SymbolTable
  -> ProcedureAst
  -> Either [Diagnostic] ProcedureIR
compileProcedure symbols procedure = do
  branches <- mapM (compileBranch symbols) (procedureBranches procedure)
  pure $
    ProcedureIR
      { procedureIrName = procedureName procedure
      , procedureIrBranches = branches
      }

compileBranch :: SymbolTable -> [ActionPhraseAst] -> Either [Diagnostic] (Act Active)
compileBranch symbols actions = do
  resolvedActions <- mapM (resolveAction symbols) actions
  pure (normalizeAct (Seq (map resolvedActionToAct resolvedActions)))

compileRuleSpec
  :: LawMetaAst
  -> SymbolTable
  -> RuleAst
  -> Either [Diagnostic] RuleSpec
compileRuleSpec meta symbols ruleAst = do
  condition <- resolveCondition symbols (ruleConditionAst ruleAst)
  consequent <- compileModality meta symbols (ruleConsequentAst ruleAst)
  pure $
    RuleSpec
      { ruleSpecName = ruleNameAst ruleAst
      , ruleSpecCondition = condition
      , ruleSpecConsequent = consequent
      }

resolveAction :: SymbolTable -> ActionPhraseAst -> Either [Diagnostic] ResolvedAction
resolveAction symbols action = do
  actor <- liftDiagnostic (resolvePartyDecl symbols (actionActorName action))
  objectDecl <- liftDiagnostic (resolveObjectDecl symbols (actionObjectName action))
  _ <- liftDiagnostic (resolveVerbCanonical symbols (actionVerb action))
  targetName <-
    case actionTargetName action of
      Just name -> Right name
      Nothing ->
        Left
          [ Diagnostic "resolution"
              ("missing target for action by `" ++ actionActorName action ++ "`")
          ]
  target <- liftDiagnostic (resolvePartyDecl symbols targetName)
  pure $
    ResolvedAction
      { resolvedActionVerb = normalizeVerbToken (actionVerb action)
      , resolvedActionActor = mkPerson actor
      , resolvedActionObject = mkObject (objectKind objectDecl) (actionObjectName action)
      , resolvedActionTarget = mkPerson target
      }

resolveClaim :: SymbolTable -> ClaimPhraseAst -> Either [Diagnostic] ResolvedClaim
resolveClaim symbols claimAst = do
  holder <- liftDiagnostic (resolvePartyDecl symbols (claimHolderName claimAst))
  against <- liftDiagnostic (resolvePartyDecl symbols (claimAgainstName claimAst))
  objectDecl <- liftDiagnostic (resolveObjectDecl symbols (claimObjectName claimAst))
  _ <- liftDiagnostic (resolveVerbCanonical symbols (claimVerb claimAst))
  pure $
    ResolvedClaim
      { resolvedClaimVerb = normalizeVerbToken (claimVerb claimAst)
      , resolvedClaimHolder = mkPerson holder
      , resolvedClaimAgainst = mkPerson against
      , resolvedClaimObject = mkObject (objectKind objectDecl) (claimObjectName claimAst)
      }

resolveCondition :: SymbolTable -> ConditionAst -> Either [Diagnostic] ResolvedCondition
resolveCondition symbols conditionAst =
  case conditionAst of
    OwnershipConditionAst partyName objectName -> do
      party <- liftDiagnostic (resolvePartyDecl symbols partyName)
      objectDecl <- liftDiagnostic (resolveObjectDecl symbols objectName)
      pure $
        ResolvedOwnershipCondition
          (mkPerson party)
          (mkObject (objectKind objectDecl) objectName)

resolvedActionToAct :: ResolvedAction -> Act Active
resolvedActionToAct action =
  normalizeAct $
    Simple
      (resolvedActionActor action)
      (resolvedActionObject action)
      (resolvedActionTarget action)

resolvedClaimToAct :: ResolvedClaim -> Act Active
resolvedClaimToAct claim =
  normalizeAct $
    Simple
      (resolvedClaimAgainst claim)
      (resolvedClaimObject claim)
      (resolvedClaimHolder claim)

mkPerson :: PartyDecl -> Person
mkPerson party =
  Person
    { pSubtype = Physical
    , pName = partyDisplayName party
    , pCapacity = Exercise
    , pAddress = ""
    }

mkObject :: ObjectKindAst -> String -> Object
mkObject kind objectName =
  Object
    { oSubtype = compileObjectSubtype kind
    , oName = objectName
    , oStart = epoch
    , oDue = epoch
    , oEnd = Nothing
    }
  where
    epoch = toEpochDay

compileObjectSubtype :: ObjectKindAst -> OSubtype
compileObjectSubtype kind =
  case kind of
    MovableKind -> ThingSubtype Movable
    NonMovableKind -> ThingSubtype NonMovable
    ExpendableKind -> ThingSubtype Expendable
    MoneyKind -> ThingSubtype Expendable
    ServiceKind -> ServiceSubtype (Performance Nothing)

toEpochDay :: Day
toEpochDay = fromGregorian 1 1 1

liftDiagnostic :: Either Diagnostic a -> Either [Diagnostic] a
liftDiagnostic =
  either (Left . (: [])) Right

extractFact :: ClauseResult -> Maybe IndexedGen
extractFact clauseResult =
  case clauseResult of
    CompiledFact fact -> Just fact
    _ -> Nothing

extractProcedure :: ClauseResult -> Maybe ProcedureIR
extractProcedure clauseResult =
  case clauseResult of
    CompiledProcedure procedure -> Just procedure
    _ -> Nothing

extractRule :: ClauseResult -> Maybe RuleSpec
extractRule clauseResult =
  case clauseResult of
    CompiledRule ruleSpec -> Just ruleSpec
    _ -> Nothing

gatherErrors :: [Either [Diagnostic] a] -> [Diagnostic]
gatherErrors values =
  concat lefts
  where
    (lefts, _) = partitionEithers values

gatherValues :: [Either [Diagnostic] a] -> [a]
gatherValues values =
  rights
  where
    (_, rights) = partitionEithers values
