module Compiler.Compiler
  ( CompiledLawModule(..)
  , DisplayVerbMap(..)
  , IntrinsicArg(..)
  , ProcedureIR(..)
  , ResolvedAct(..)
  , ResolvedAction(..)
  , ResolvedClaim(..)
  , ResolvedCondition(..)
  , RuleSpec(..)
  , compileInitialNorm
  , compileInitialSystemState
  , compileLawModule
  , resolveAction
  , resolveCondition
  , resolvedActionToAct
  , resolvedActionToCounterAct
  ) where

import Compiler.AST
import Compiler.SymbolTable
import Data.Either (partitionEithers)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Time.Calendar (Day, fromGregorian)
import LegalOntology
import Logic (SystemState(..))
import NormativeGenerators
import qualified Patrimony as P

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

data ResolvedAct
  = ResolvedActiveAct (Act Active)
  | ResolvedPassiveAct (Act Passive)
  deriving (Eq, Show)

data IntrinsicArg
  = ResolvedIntrinsicFactRef String
  | ResolvedIntrinsicLiteral Double
  | ResolvedIntrinsicDateLiteral Day
  deriving (Eq, Show)

data ResolvedCondition
  = ResolvedOwnershipCondition Person Object
  | ResolvedCapabilityCondition CapabilityIndex
  | ResolvedAssetCondition String
  | ResolvedLiabilityCondition String
  | ResolvedCollateralCondition String
  | ResolvedCertificationCondition String
  | ResolvedApprovedContractorCondition String
  | ResolvedActionCondition ResolvedAct
  | ResolvedEventCondition LegalEvent
  | ResolvedIntrinsicPredicate String [IntrinsicArg]
  | ResolvedConjunction [ResolvedCondition]
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

newtype DisplayVerbMap = DisplayVerbMap (M.Map (String, String) String)
  deriving (Eq, Show)

data CompiledLawModule = CompiledLawModule
  { compiledMetadata :: LawMetaAst
  , compiledFacts :: [IndexedGen]
  , compiledInstitutionalFacts :: P.PatrimonyState
  , compiledProcedures :: [ProcedureIR]
  , compiledRules :: [RuleSpec]
  , compiledDisplayVerbMap :: DisplayVerbMap
  }
  deriving (Eq, Show)
  -- Note: compiledDisplayVerbMap is excluded from Eq/Show by using a wrapper

data ClauseResult
  = CompiledFact IndexedGen
  | CompiledInstitutionalFact P.PatrimonyGen
  | CompiledProcedure ProcedureIR
  | CompiledRule RuleSpec

compileLawModule :: LawModuleAst -> Either [Diagnostic] CompiledLawModule
compileLawModule lawModule = do
  symbols <- buildSymbolTable lawModule
  let sourcedClauses =
        [ (sourceMeta sourcedArticle, clause)
        | sourcedArticle <- lawArticles lawModule
        , clause <- articleClauses (sourcePayload sourcedArticle)
        ]
      results = map (\(meta, clause) -> compileClause meta symbols clause) sourcedClauses
      diagnostics = gatherErrors results
      payloads = gatherValues results
  case diagnostics of
    [] ->
      Right $
        CompiledLawModule
          { compiledMetadata = lawMeta lawModule
          , compiledFacts = mapMaybe extractFact payloads
          , compiledInstitutionalFacts =
              S.fromList (mapMaybe extractInstitutionalFact payloads)
          , compiledProcedures = mapMaybe extractProcedure payloads
          , compiledRules = mapMaybe extractRule payloads
          , compiledDisplayVerbMap = buildDisplayVerbMap lawModule symbols payloads
          }
    errs -> Left errs

buildDisplayVerbMap :: LawModuleAst -> SymbolTable -> [ClauseResult] -> DisplayVerbMap
buildDisplayVerbMap lawModule symbols _payloads =
  DisplayVerbMap (M.fromList verbEntries)
  where
    verbEntries =
        [ ((oName obj, baseVerbForObject obj), actionVerb actionAst)
        | sourcedArticle <- lawArticles lawModule
        , clause <- articleClauses (sourcePayload sourcedArticle)
        , (actionAst, obj) <- extractActionObjects symbols clause
        ]
    extractActionObjects symbols clause =
      case clause of
        ClauseModality (ObligationAst a) -> extractAction symbols a
        ClauseModality (ProhibitionAst a) -> extractAction symbols a
        ClauseModality (PrivilegeAst a) -> extractAction symbols a
        ClauseRule r -> extractAction symbols (modalityAction (ruleConsequentAst r))
        ClauseOverride o -> extractAction symbols (modalityAction (overrideTargetAst o))
        ClauseSuspend s -> extractAction symbols (modalityAction (suspendTargetAst s))
        _ -> []
    modalityAction (ObligationAst a) = a
    modalityAction (ProhibitionAst a) = a
    modalityAction (PrivilegeAst a) = a
    modalityAction (ClaimAst c) =
      ActionPhraseAst
        { actionActorName = claimAgainstName c
        , actionVerb = claimVerb c
        , actionObjectName = claimObjectName c
        , actionTargetName = Just (claimHolderName c)
        , actionPolarity = PositiveActionAst
        }
    extractAction symbols actionAst =
      case resolveObjectDecl symbols (actionObjectName actionAst) of
        Right objectDecl ->
          case compileObjectDecl symbols objectDecl of
            Right obj -> [(actionAst, obj)]
            Left _ -> []
        Left _ -> []
    baseVerbForObject obj =
      case oSubtype obj of
        ThingSubtype Expendable -> "transfer"
        ThingSubtype _ -> "deliver"
        ServiceSubtype (Performance (Just _)) -> "deliver"
        ServiceSubtype (Performance Nothing) -> "perform"
        ServiceSubtype (Omission (Just _)) -> "refrain from interfering with"
        ServiceSubtype (Omission Nothing) -> "refrain from"

compileInitialNorm :: LawModuleAst -> Either [Diagnostic] Norm
compileInitialNorm lawModule = do
  compiled <- compileLawModule lawModule
  pure (S.fromList (compiledFacts compiled))

compileInitialSystemState :: LawModuleAst -> Either [Diagnostic] SystemState
compileInitialSystemState lawModule = do
  compiled <- compileLawModule lawModule
  pure $
    SystemState
      { normState = S.fromList (compiledFacts compiled)
      , patrState = compiledInstitutionalFacts compiled
      }

compileClause
  :: LawMetaAst
  -> SymbolTable
  -> ClauseAst
  -> Either [Diagnostic] ClauseResult
compileClause meta symbols clause =
  case clause of
    ClauseModality modality ->
      CompiledFact <$> compileModality meta symbols modality
    ClauseStandingFact factAst ->
      CompiledInstitutionalFact <$> compileStandingFact symbols factAst
    ClauseProcedure procedure ->
      CompiledProcedure <$> compileProcedure symbols procedure
    ClauseRule ruleAst ->
      CompiledRule <$> compileRuleSpec meta symbols ruleAst
    ClauseOverride overrideAst ->
      CompiledRule <$> compileOverrideSpec meta symbols overrideAst
    ClauseSuspend suspendAst ->
      CompiledRule <$> compileSuspendSpec meta symbols suspendAst

compileModality
  :: LawMetaAst
  -> SymbolTable
  -> ModalityAst
  -> Either [Diagnostic] IndexedGen
compileModality meta symbols modality =
  case modality of
    ObligationAst action -> do
      resolved <- resolveAction symbols action
      pure $
        indexedGen (lawAuthorityAst meta) (lawEnactedAst meta)
          (obligationGenerator action resolved)
    ClaimAst claimAst ->
      indexedGen (lawAuthorityAst meta) (lawEnactedAst meta)
        . GClaim . Claim . resolvedClaimToAct
        <$> resolveClaim symbols claimAst
    ProhibitionAst action -> do
      resolved <- resolveAction symbols action
      pure $
        indexedGen (lawAuthorityAst meta) (lawEnactedAst meta)
          (prohibitionGenerator action resolved)
    PrivilegeAst action -> do
      resolved <- resolveAction symbols action
      pure $
        indexedGen (lawAuthorityAst meta) (lawEnactedAst meta)
          (privilegeGenerator action resolved)

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
  activeActs <- mapM ensureActiveProcedureStep (zip actions resolvedActions)
  pure (normalizeAct (Seq activeActs))

compileRuleSpec
  :: LawMetaAst
  -> SymbolTable
  -> RuleAst
  -> Either [Diagnostic] RuleSpec
compileRuleSpec meta symbols ruleAst = do
  condition <- resolveCondition symbols (ruleConditionAst ruleAst)
  baseConsequent <- compileModality meta symbols (ruleConsequentAst ruleAst)
  let validFrom = ruleValidFromAst ruleAst
      validTo = ruleValidToAst ruleAst
      consequent =
        baseConsequent
          { time = fromMaybe (time baseConsequent) validFrom
          }
  pure $
    RuleSpec
      { ruleSpecName = ruleNameAst ruleAst
      , ruleSpecCondition = condition
      , ruleSpecConsequent = consequent
      }

modalitySummary :: ModalityAst -> String
modalitySummary modAst =
  case modAst of
    ObligationAst a -> actionSummary a
    ClaimAst c -> claimHolderName c ++ "_" ++ claimVerb c
    ProhibitionAst a -> actionSummary a
    PrivilegeAst a -> actionSummary a

actionSummary :: ActionPhraseAst -> String
actionSummary a =
  actionActorName a ++ "_" ++ actionVerb a ++ "_" ++ actionObjectName a

compileOverrideSpec
  :: LawMetaAst
  -> SymbolTable
  -> OverrideClauseAst
  -> Either [Diagnostic] RuleSpec
compileOverrideSpec meta symbols overrideAst = do
  condition <- resolveCondition symbols (overrideConditionAst overrideAst)
  targetGen <- compileModality meta symbols (overrideTargetAst overrideAst)
  let overriddenGen =
        targetGen { gen = Overridden (gen targetGen) }
  pure $
    RuleSpec
      { ruleSpecName = "override:" ++ modalitySummary (overrideTargetAst overrideAst)
      , ruleSpecCondition = condition
      , ruleSpecConsequent = overriddenGen
      }

compileSuspendSpec
  :: LawMetaAst
  -> SymbolTable
  -> SuspendClauseAst
  -> Either [Diagnostic] RuleSpec
compileSuspendSpec meta symbols suspendAst = do
  condition <- resolveCondition symbols (suspendConditionAst suspendAst)
  targetGen <- compileModality meta symbols (suspendTargetAst suspendAst)
  let overriddenGen =
        targetGen { gen = Overridden (gen targetGen) }
  pure $
    RuleSpec
      { ruleSpecName = "suspend:" ++ modalitySummary (suspendTargetAst suspendAst)
      , ruleSpecCondition = condition
      , ruleSpecConsequent = overriddenGen
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
  objectValue <- compileObjectDecl symbols objectDecl
  pure $
    ResolvedAction
      { resolvedActionVerb = normalizeVerbToken (actionVerb action)
      , resolvedActionActor = mkPerson actor
      , resolvedActionObject = objectValue
      , resolvedActionTarget = mkPerson target
      }

resolveClaim :: SymbolTable -> ClaimPhraseAst -> Either [Diagnostic] ResolvedClaim
resolveClaim symbols claimAst = do
  holder <- liftDiagnostic (resolvePartyDecl symbols (claimHolderName claimAst))
  against <- liftDiagnostic (resolvePartyDecl symbols (claimAgainstName claimAst))
  objectDecl <- liftDiagnostic (resolveObjectDecl symbols (claimObjectName claimAst))
  _ <- liftDiagnostic (resolveVerbCanonical symbols (claimVerb claimAst))
  objectValue <- compileObjectDecl symbols objectDecl
  pure $
    ResolvedClaim
      { resolvedClaimVerb = normalizeVerbToken (claimVerb claimAst)
      , resolvedClaimHolder = mkPerson holder
      , resolvedClaimAgainst = mkPerson against
      , resolvedClaimObject = objectValue
      }

resolveCondition :: SymbolTable -> ConditionAst -> Either [Diagnostic] ResolvedCondition
resolveCondition symbols conditionAst =
  case conditionAst of
    InstitutionalConditionAst factAst ->
      resolveInstitutionalCondition symbols factAst
    ActionConditionAst actionAst ->
      ResolvedActionCondition <$> resolveActionCondition symbols actionAst
    EventConditionAst eventAst ->
      pure (ResolvedEventCondition (legalEventAstToEvent eventAst))
    IntrinsicConditionAst name args ->
      pure (ResolvedIntrinsicPredicate name (map intrinsicArgAstToArg args))
    ConditionConjunctionAst conditions ->
      ResolvedConjunction <$> mapM (resolveCondition symbols) conditions

intrinsicArgAstToArg :: IntrinsicArgAst -> IntrinsicArg
intrinsicArgAstToArg arg =
  case arg of
    IntrinsicFactRef name -> ResolvedIntrinsicFactRef name
    IntrinsicNumericLiteral d -> ResolvedIntrinsicLiteral d
    IntrinsicDateLiteral day -> ResolvedIntrinsicDateLiteral day

resolveInstitutionalCondition
  :: SymbolTable
  -> StandingFactAst
  -> Either [Diagnostic] ResolvedCondition
resolveInstitutionalCondition symbols factAst =
  case factAst of
    OwnershipFactAst partyName objectName -> do
      party <- liftDiagnostic (resolvePartyDecl symbols partyName)
      objectDecl <- liftDiagnostic (resolveObjectDecl symbols objectName)
      objectValue <- compileObjectDecl symbols objectDecl
      pure (ResolvedOwnershipCondition (mkPerson party) objectValue)
    CapabilityFactAst capability ->
      pure (ResolvedCapabilityCondition capability)
    AssetFactAst assetName ->
      pure (ResolvedAssetCondition assetName)
    LiabilityFactAst liabilityName ->
      pure (ResolvedLiabilityCondition liabilityName)
    CollateralFactAst collateralName ->
      pure (ResolvedCollateralCondition collateralName)
    CertificationFactAst certificationName ->
      pure (ResolvedCertificationCondition certificationName)
    ApprovedContractorFactAst contractorName ->
      pure (ResolvedApprovedContractorCondition contractorName)

resolveActionCondition :: SymbolTable -> ActionPhraseAst -> Either [Diagnostic] ResolvedAct
resolveActionCondition symbols actionAst = do
  resolved <- resolveAction symbols actionAst
  pure (resolvedActionFromPhrase actionAst resolved)

resolvedActionToAct :: ResolvedAction -> Act Active
resolvedActionToAct action =
  normalizeAct $
    Simple
      (resolvedActionActor action)
      (resolvedActionObject action)
      (resolvedActionTarget action)

resolvedActionToCounterAct :: ResolvedAction -> Act Passive
resolvedActionToCounterAct action =
  normalizeAct $
    Counter
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

legalEventAstToEvent :: LegalEventAst -> LegalEvent
legalEventAstToEvent ast =
  case ast of
    HumanEventAst desc -> HumanAct desc
    NaturalEventAst desc -> NaturalFact desc

resolvedActionFromPhrase :: ActionPhraseAst -> ResolvedAction -> ResolvedAct
resolvedActionFromPhrase actionAst resolved =
  case actionPolarity actionAst of
    PositiveActionAst -> ResolvedActiveAct (resolvedActionToAct resolved)
    NegativeActionAst -> ResolvedPassiveAct (resolvedActionToCounterAct resolved)

mkPerson :: PartyDecl -> Person
mkPerson party =
  Person
    { pSubtype =
        case partySubtypeAst party of
          NaturalPartyAst -> Physical
          LegalPartyAst -> Legal
    , pName = partyDisplayName party
    , pCapacity =
        case partyCapacityAst party of
          EnjoyCapacityAst -> Enjoy
          ExerciseCapacityAst -> Exercise
    , pAddress = fromMaybe "" (partyAddressAst party)
    }

compileObjectDecl :: SymbolTable -> ObjectDecl -> Either [Diagnostic] Object
compileObjectDecl symbols objectDecl = do
  relatedObject <-
    case objectRelatedObject objectDecl of
      Nothing -> Right Nothing
      Just relatedAlias
        | normalizeSymbolKey relatedAlias == normalizeSymbolKey (objectAlias objectDecl) ->
            Left
              [ Diagnostic "resolution"
                  ("object `" ++ objectAlias objectDecl ++ "` cannot relate to itself")
              ]
        | otherwise -> do
            relatedDecl <- liftDiagnostic (resolveObjectDecl symbols relatedAlias)
            Just <$> compileObjectDecl symbols relatedDecl
  pure (mkObject objectDecl relatedObject)

mkObject :: ObjectDecl -> Maybe Object -> Object
mkObject objectDecl relatedObject =
  Object
    { oSubtype = compileObjectSubtype objectDecl relatedObject
    , oName = objectAlias objectDecl
    , oStart = fromMaybe epoch (objectStartAst objectDecl)
    , oDue =
        fromMaybe
          (fromMaybe epoch (objectStartAst objectDecl))
          (objectDueAst objectDecl)
    , oEnd = objectEndAst objectDecl
    }
  where
    epoch = toEpochDay

compileObjectSubtype :: ObjectDecl -> Maybe Object -> OSubtype
compileObjectSubtype objectDecl relatedObject =
  case objectKind objectDecl of
    MovableKind -> ThingSubtype Movable
    NonMovableKind -> ThingSubtype NonMovable
    ExpendableKind -> ThingSubtype Expendable
    MoneyKind -> ThingSubtype Expendable
    ServiceKind ->
      ServiceSubtype $
        case fromMaybe PerformanceServiceAst (objectServiceMode objectDecl) of
          PerformanceServiceAst -> Performance relatedObject
          OmissionServiceAst -> Omission relatedObject

compileStandingFact
  :: SymbolTable
  -> StandingFactAst
  -> Either [Diagnostic] P.PatrimonyGen
compileStandingFact symbols factAst =
  case factAst of
    OwnershipFactAst _ objectName -> do
      objectDecl <- liftDiagnostic (resolveObjectDecl symbols objectName)
      P.Owned <$> compileObjectDecl symbols objectDecl
    CapabilityFactAst capability ->
      pure (P.Capability (capabilityToken capability))
    AssetFactAst assetName ->
      pure (P.Asset assetName)
    LiabilityFactAst liabilityName ->
      pure (P.Liability liabilityName)
    CollateralFactAst collateralName ->
      pure (P.Collateral collateralName)
    CertificationFactAst certificationName ->
      pure (P.Certification certificationName)
    ApprovedContractorFactAst contractorName ->
      pure (P.ApprovedContractor contractorName)

capabilityToken :: CapabilityIndex -> String
capabilityToken capability =
  case capability of
    BaseAuthority -> "baseauthority"
    PrivatePower -> "private"
    LegislativePower -> "legislative"
    JudicialPower -> "judicial"
    AdministrativePower -> "administrative"
    ConstitutionalPower -> "constitutional"

obligationGenerator :: ActionPhraseAst -> ResolvedAction -> Generator
obligationGenerator actionAst resolved =
  case resolvedActionFromPhrase actionAst resolved of
    ResolvedActiveAct act -> GObligation (Obligation act)
    ResolvedPassiveAct act -> GObligation (Obligation act)

prohibitionGenerator :: ActionPhraseAst -> ResolvedAction -> Generator
prohibitionGenerator actionAst resolved =
  case resolvedActionFromPhrase actionAst resolved of
    ResolvedActiveAct act -> GProhibition (Prohibition act)
    ResolvedPassiveAct act -> GProhibition (Prohibition act)

privilegeGenerator :: ActionPhraseAst -> ResolvedAction -> Generator
privilegeGenerator actionAst resolved =
  case resolvedActionFromPhrase actionAst resolved of
    ResolvedActiveAct act -> GPrivilege (Privilege act)
    ResolvedPassiveAct act -> GPrivilege (Privilege act)

ensureActiveProcedureStep
  :: (ActionPhraseAst, ResolvedAction)
  -> Either [Diagnostic] (Act Active)
ensureActiveProcedureStep (actionAst, resolved) =
  case resolvedActionFromPhrase actionAst resolved of
    ResolvedActiveAct act -> Right act
    ResolvedPassiveAct _ ->
      Left
        [ Diagnostic "procedure"
            ("procedure steps must be positive acts, but `" ++ actionVerb actionAst ++ "` was expressed as a counter-act")
        ]

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

extractInstitutionalFact :: ClauseResult -> Maybe P.PatrimonyGen
extractInstitutionalFact clauseResult =
  case clauseResult of
    CompiledInstitutionalFact fact -> Just fact
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
