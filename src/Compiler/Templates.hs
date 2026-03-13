module Compiler.Templates
  ( expandTemplates
  ) where

import Compiler.AST
import Compiler.SymbolTable (Diagnostic(..), normalizeSymbolKey)
import Data.List (foldl')
import qualified Data.Map.Strict as M

type TemplateEnv = M.Map String (Sourced TemplateDeclAst)
type TemplateBindings = M.Map String String

expandTemplates :: SurfaceLawModuleAst -> Either [Diagnostic] LawModuleAst
expandTemplates surfaceLaw = do
  templateEnv <- collectTemplates (surfaceTopForms surfaceLaw)
  expandedForms <- expandTopForms templateEnv [] (surfaceTopForms surfaceLaw)
  pure (materializeLawModule (surfaceLawMeta surfaceLaw) expandedForms)

collectTemplates :: [Sourced TopFormAst] -> Either [Diagnostic] TemplateEnv
collectTemplates =
  foldl' step (Right M.empty)
  where
    step (Left diagnostics) _ = Left diagnostics
    step (Right env) sourcedForm =
      case sourcePayload sourcedForm of
        TopFormTemplate templateDecl ->
          let key = normalizeSymbolKey (templateNameAst templateDecl)
          in case M.lookup key env of
               Just _ ->
                 Left
                   [ Diagnostic "template"
                       ("duplicate template `" ++ templateNameAst templateDecl ++ "`")
                   ]
               Nothing ->
                 case duplicateParams (templateParamsAst templateDecl) of
                   [] -> Right (M.insert key (mapSourced (const templateDecl) sourcedForm) env)
                   duplicates ->
                     Left
                       [ Diagnostic "template"
                           ("duplicate template parameter `" ++ duplicateName ++ "` in `" ++ templateNameAst templateDecl ++ "`")
                       | duplicateName <- duplicates
                       ]
        _ -> Right env

duplicateParams :: [String] -> [String]
duplicateParams params =
  M.keys (M.filter (> (1 :: Int)) counts)
  where
    counts =
      foldl'
        (\acc paramName -> M.insertWith (+) (normalizeSymbolKey paramName) 1 acc)
        M.empty
        params

expandTopForms
  :: TemplateEnv
  -> [String]
  -> [Sourced TopFormAst]
  -> Either [Diagnostic] [Sourced TopFormAst]
expandTopForms templateEnv stack =
  fmap concat . mapM (expandTopForm templateEnv stack)

expandTopForm
  :: TemplateEnv
  -> [String]
  -> Sourced TopFormAst
  -> Either [Diagnostic] [Sourced TopFormAst]
expandTopForm templateEnv stack sourcedForm =
  case sourcePayload sourcedForm of
    TopFormImport _ ->
      Left
        [ Diagnostic "import"
            ("unresolved import remained after composition in `" ++ sourcePath sourcedForm ++ "`")
        ]
    TopFormTemplate _ ->
      Right []
    TopFormInstantiate instantiation ->
      expandInstantiation templateEnv stack M.empty instantiation
    _ ->
      Right [sourcedForm]

expandInstantiation
  :: TemplateEnv
  -> [String]
  -> TemplateBindings
  -> TemplateInstantiateAst
  -> Either [Diagnostic] [Sourced TopFormAst]
expandInstantiation templateEnv stack outerBindings instantiation = do
  let substitutedInstantiation = substituteInstantiation outerBindings instantiation
      templateKey = normalizeSymbolKey (instantiateTemplateName substitutedInstantiation)
  sourcedTemplate <-
    case M.lookup templateKey templateEnv of
      Just template -> Right template
      Nothing ->
        Left
          [ Diagnostic "template"
              ("unknown template `" ++ instantiateTemplateName substitutedInstantiation ++ "`")
          ]
  let templateDecl = sourcePayload sourcedTemplate
  if templateKey `elem` stack
    then
      Left
        [ Diagnostic "template"
            ("recursive template instantiation involving `" ++ templateNameAst templateDecl ++ "`")
        ]
    else do
      bindingEnv <- buildBindingEnv templateDecl substitutedInstantiation
      expandTemplateBody templateEnv (templateKey : stack) sourcedTemplate bindingEnv (templateBodyAst templateDecl)

buildBindingEnv
  :: TemplateDeclAst
  -> TemplateInstantiateAst
  -> Either [Diagnostic] TemplateBindings
buildBindingEnv templateDecl instantiation =
  case duplicateBindingNames of
    duplicateName : _ ->
      Left
        [ Diagnostic "template"
            ("duplicate binding `" ++ duplicateName ++ "` in instantiation of `" ++ templateNameAst templateDecl ++ "`")
        ]
    [] ->
      case unknownBindings of
        unknownName : _ ->
          Left
            [ Diagnostic "template"
                ("unknown binding `" ++ unknownName ++ "` for template `" ++ templateNameAst templateDecl ++ "`")
            ]
        [] ->
          case missingParams of
            missingName : _ ->
              Left
                [ Diagnostic "template"
                    ("missing binding for parameter `" ++ missingName ++ "` in instantiation of `" ++ templateNameAst templateDecl ++ "`")
                ]
            [] ->
              Right
                (M.fromList
                  [ (paramName, bindingLookup M.! normalizeSymbolKey paramName)
                  | paramName <- templateParamsAst templateDecl
                  ])
  where
    bindingPairs =
      [ (normalizeSymbolKey (bindingParamName binding), bindingValueText binding)
      | binding <- instantiateBindings instantiation
      ]
    bindingLookup = M.fromList bindingPairs
    bindingKeys = map fst bindingPairs
    duplicateBindingNames = duplicates bindingKeys
    templateParamKeys = map normalizeSymbolKey (templateParamsAst templateDecl)
    unknownBindings =
      [ bindingParamName binding
      | binding <- instantiateBindings instantiation
      , normalizeSymbolKey (bindingParamName binding) `notElem` templateParamKeys
      ]
    missingParams =
      [ paramName
      | paramName <- templateParamsAst templateDecl
      , normalizeSymbolKey paramName `M.notMember` bindingLookup
      ]

duplicates :: [String] -> [String]
duplicates values =
  M.keys (M.filter (> (1 :: Int)) counts)
  where
    counts =
      foldl'
        (\acc value -> M.insertWith (+) value 1 acc)
        M.empty
        values

expandTemplateBody
  :: TemplateEnv
  -> [String]
  -> Sourced TemplateDeclAst
  -> TemplateBindings
  -> [TemplateBodyFormAst]
  -> Either [Diagnostic] [Sourced TopFormAst]
expandTemplateBody templateEnv stack sourcedTemplate bindings =
  fmap concat . mapM (expandTemplateBodyForm templateEnv stack sourcedTemplate bindings)

expandTemplateBodyForm
  :: TemplateEnv
  -> [String]
  -> Sourced TemplateDeclAst
  -> TemplateBindings
  -> TemplateBodyFormAst
  -> Either [Diagnostic] [Sourced TopFormAst]
expandTemplateBodyForm templateEnv stack sourcedTemplate bindings templateBodyForm =
  case templateBodyForm of
    TemplateBodyParties parties ->
      Right [withSource (TopFormParties (map (substituteParty bindings) parties))]
    TemplateBodyObjects objects ->
      Right [withSource (TopFormObjects (map (substituteObjectDecl bindings) objects))]
    TemplateBodyVocabulary vocabulary ->
      Right [withSource (TopFormVocabulary (map (substituteVocabularyDecl bindings) vocabulary))]
    TemplateBodyFacts facts ->
      Right [withSource (TopFormFacts (map (substituteFactDecl bindings) facts))]
    TemplateBodyArticle article ->
      Right [withSource (TopFormArticle (substituteArticle bindings article))]
    TemplateBodyScenario scenario ->
      Right [withSource (TopFormScenario (substituteScenario bindings scenario))]
    TemplateBodyInstantiate instantiation ->
      expandInstantiation templateEnv stack bindings instantiation
  where
    withSource payload =
      Sourced
        { sourceMeta = sourceMeta sourcedTemplate
        , sourcePath = sourcePath sourcedTemplate
        , sourcePayload = payload
        }

materializeLawModule :: LawMetaAst -> [Sourced TopFormAst] -> LawModuleAst
materializeLawModule meta topForms =
  foldl' step emptyLaw topForms
  where
    emptyLaw =
      LawModuleAst
        { lawMeta = meta
        , lawParties = []
        , lawObjects = []
        , lawVocabulary = []
        , lawFacts = []
        , lawArticles = []
        , lawScenarios = []
        }

    step lawModule sourcedForm =
      case sourcePayload sourcedForm of
        TopFormImport _ ->
          lawModule
        TopFormParties parties ->
          lawModule { lawParties = lawParties lawModule ++ parties }
        TopFormObjects objects ->
          lawModule { lawObjects = lawObjects lawModule ++ objects }
        TopFormVocabulary vocabulary ->
          lawModule { lawVocabulary = lawVocabulary lawModule ++ vocabulary }
        TopFormFacts facts ->
          lawModule { lawFacts = lawFacts lawModule ++ facts }
        TopFormArticle article ->
          lawModule { lawArticles = lawArticles lawModule ++ [mapSourced (const article) sourcedForm] }
        TopFormScenario scenario ->
          lawModule { lawScenarios = lawScenarios lawModule ++ [mapSourced (const scenario) sourcedForm] }
        TopFormTemplate _ ->
          lawModule
        TopFormInstantiate _ ->
          lawModule

mapSourced :: (a -> b) -> Sourced a -> Sourced b
mapSourced transform sourcedValue =
  Sourced
    { sourceMeta = sourceMeta sourcedValue
    , sourcePath = sourcePath sourcedValue
    , sourcePayload = transform (sourcePayload sourcedValue)
    }

substituteParty :: TemplateBindings -> PartyDecl -> PartyDecl
substituteParty bindings party =
  party
    { partyAlias = substituteText bindings (partyAlias party)
    , partyDisplayName = substituteText bindings (partyDisplayName party)
    , partyAddressAst = fmap (substituteText bindings) (partyAddressAst party)
    }

substituteObjectDecl :: TemplateBindings -> ObjectDecl -> ObjectDecl
substituteObjectDecl bindings objectDecl =
  objectDecl
    { objectAlias = substituteText bindings (objectAlias objectDecl)
    , objectRelatedObject = fmap (substituteText bindings) (objectRelatedObject objectDecl)
    }

substituteVocabularyDecl :: TemplateBindings -> VocabularyDecl -> VocabularyDecl
substituteVocabularyDecl bindings vocabularyDecl =
  case vocabularyDecl of
    VerbVocabulary surface canonical ->
      VerbVocabulary
        (substituteText bindings surface)
        (substituteText bindings canonical)
    ObjectVocabulary surface canonical ->
      ObjectVocabulary
        (substituteText bindings surface)
        (substituteText bindings canonical)

substituteFactDecl :: TemplateBindings -> FactDecl -> FactDecl
substituteFactDecl bindings fact =
  fact { factDeclName = substituteText bindings (factDeclName fact) }

substituteAction :: TemplateBindings -> ActionPhraseAst -> ActionPhraseAst
substituteAction bindings action =
  action
    { actionActorName = substituteText bindings (actionActorName action)
    , actionVerb = substituteText bindings (actionVerb action)
    , actionObjectName = substituteText bindings (actionObjectName action)
    , actionTargetName = fmap (substituteText bindings) (actionTargetName action)
    }

substituteClaim :: TemplateBindings -> ClaimPhraseAst -> ClaimPhraseAst
substituteClaim bindings claim =
  claim
    { claimHolderName = substituteText bindings (claimHolderName claim)
    , claimVerb = substituteText bindings (claimVerb claim)
    , claimObjectName = substituteText bindings (claimObjectName claim)
    , claimAgainstName = substituteText bindings (claimAgainstName claim)
    }

substituteModality :: TemplateBindings -> ModalityAst -> ModalityAst
substituteModality bindings modality =
  case modality of
    ObligationAst action -> ObligationAst (substituteAction bindings action)
    ClaimAst claim -> ClaimAst (substituteClaim bindings claim)
    ProhibitionAst action -> ProhibitionAst (substituteAction bindings action)
    PrivilegeAst action -> PrivilegeAst (substituteAction bindings action)

substituteProcedure :: TemplateBindings -> ProcedureAst -> ProcedureAst
substituteProcedure bindings procedure =
  procedure
    { procedureName = substituteText bindings (procedureName procedure)
    , procedureBranches =
        map (map (substituteAction bindings)) (procedureBranches procedure)
    }

substituteStandingFact :: TemplateBindings -> StandingFactAst -> StandingFactAst
substituteStandingFact bindings standingFact =
  case standingFact of
    OwnershipFactAst partyName objectName ->
      OwnershipFactAst
        (substituteText bindings partyName)
        (substituteText bindings objectName)
    CapabilityFactAst capability ->
      CapabilityFactAst capability
    AssetFactAst assetName ->
      AssetFactAst (substituteText bindings assetName)
    LiabilityFactAst liabilityName ->
      LiabilityFactAst (substituteText bindings liabilityName)
    CollateralFactAst collateralName ->
      CollateralFactAst (substituteText bindings collateralName)
    CertificationFactAst certificationName ->
      CertificationFactAst (substituteText bindings certificationName)
    ApprovedContractorFactAst contractorName ->
      ApprovedContractorFactAst (substituteText bindings contractorName)

substituteCondition :: TemplateBindings -> ConditionAst -> ConditionAst
substituteCondition bindings condition =
  case condition of
    InstitutionalConditionAst standingFact ->
      InstitutionalConditionAst (substituteStandingFact bindings standingFact)
    ActionConditionAst action ->
      ActionConditionAst (substituteAction bindings action)
    EventConditionAst event ->
      EventConditionAst (substituteLegalEvent bindings event)
    IntrinsicConditionAst name args ->
      IntrinsicConditionAst name (map (substituteIntrinsicArg bindings) args)
    ConditionConjunctionAst conditions ->
      ConditionConjunctionAst (map (substituteCondition bindings) conditions)

substituteIntrinsicArg :: TemplateBindings -> IntrinsicArgAst -> IntrinsicArgAst
substituteIntrinsicArg bindings arg =
  case arg of
    IntrinsicFactRef name -> IntrinsicFactRef (substituteText bindings name)
    IntrinsicNumericLiteral d -> IntrinsicNumericLiteral d
    IntrinsicDateLiteral day -> IntrinsicDateLiteral day

substituteRule :: TemplateBindings -> RuleAst -> RuleAst
substituteRule bindings ruleAst =
  ruleAst
    { ruleNameAst = substituteText bindings (ruleNameAst ruleAst)
    , ruleConditionAst = substituteCondition bindings (ruleConditionAst ruleAst)
    , ruleConsequentAst = substituteModality bindings (ruleConsequentAst ruleAst)
    , ruleValidFromAst = ruleValidFromAst ruleAst
    , ruleValidToAst = ruleValidToAst ruleAst
    }

substituteClause :: TemplateBindings -> ClauseAst -> ClauseAst
substituteClause bindings clause =
  case clause of
    ClauseModality modality ->
      ClauseModality (substituteModality bindings modality)
    ClauseProcedure procedure ->
      ClauseProcedure (substituteProcedure bindings procedure)
    ClauseRule ruleAst ->
      ClauseRule (substituteRule bindings ruleAst)
    ClauseStandingFact standingFact ->
      ClauseStandingFact (substituteStandingFact bindings standingFact)
    ClauseOverride overrideAst ->
      ClauseOverride
        ( OverrideClauseAst
            (substituteModality bindings (overrideTargetAst overrideAst))
            (substituteCondition bindings (overrideConditionAst overrideAst))
        )
    ClauseSuspend suspendAst ->
      ClauseSuspend
        ( SuspendClauseAst
            (substituteModality bindings (suspendTargetAst suspendAst))
            (substituteCondition bindings (suspendConditionAst suspendAst))
        )

substituteArticle :: TemplateBindings -> ArticleAst -> ArticleAst
substituteArticle bindings article =
  article
    { articleHeading = fmap (substituteText bindings) (articleHeading article)
    , articleClauses = map (substituteClause bindings) (articleClauses article)
    }

substituteLegalEvent :: TemplateBindings -> LegalEventAst -> LegalEventAst
substituteLegalEvent bindings legalEvent =
  case legalEvent of
    HumanEventAst text -> HumanEventAst (substituteText bindings text)
    NaturalEventAst text -> NaturalEventAst (substituteText bindings text)

substituteScenarioAssertion :: TemplateBindings -> ScenarioAssertionAst -> ScenarioAssertionAst
substituteScenarioAssertion bindings assertion =
  case assertion of
    ScenarioAct action ->
      ScenarioAct (substituteAction bindings action)
    ScenarioCounterAct action ->
      ScenarioCounterAct (substituteAction bindings action)
    ScenarioCondition condition ->
      ScenarioCondition (substituteCondition bindings condition)
    ScenarioNumericAssert factName value ->
      ScenarioNumericAssert (substituteText bindings factName) value
    ScenarioDateAssert factName day ->
      ScenarioDateAssert (substituteText bindings factName) day
    ScenarioEvent legalEvent ->
      ScenarioEvent (substituteLegalEvent bindings legalEvent)

substituteScenarioEntry :: TemplateBindings -> ScenarioEntryAst -> ScenarioEntryAst
substituteScenarioEntry bindings entry =
  entry
    { scenarioAssertions =
        map (substituteScenarioAssertion bindings) (scenarioAssertions entry)
    }

substituteScenario :: TemplateBindings -> ScenarioAst -> ScenarioAst
substituteScenario bindings scenario =
  scenario
    { scenarioName = substituteText bindings (scenarioName scenario)
    , scenarioEntries = map (substituteScenarioEntry bindings) (scenarioEntries scenario)
    }

substituteInstantiation :: TemplateBindings -> TemplateInstantiateAst -> TemplateInstantiateAst
substituteInstantiation bindings instantiation =
  instantiation
    { instantiateTemplateName =
        substituteText bindings (instantiateTemplateName instantiation)
    , instantiateBindings =
        map substituteBinding (instantiateBindings instantiation)
    }
  where
    substituteBinding binding =
      binding
        { bindingParamName = substituteText bindings (bindingParamName binding)
        , bindingValueText = substituteText bindings (bindingValueText binding)
        }

substituteText :: TemplateBindings -> String -> String
substituteText bindings text =
  finalizeExactMatch replaced
  where
    replaced =
      foldl'
        (\acc (paramName, valueText) -> replaceAll ("{{" ++ paramName ++ "}}") valueText acc)
        text
        (M.toList bindings)

    finalizeExactMatch currentText =
      case
        [ valueText
        | (paramName, valueText) <- M.toList bindings
        , normalizeSymbolKey currentText == normalizeSymbolKey paramName
        ] of
        valueText : _ -> valueText
        [] -> currentText

replaceAll :: String -> String -> String -> String
replaceAll needle replacement =
  go
  where
    go [] = []
    go haystack@(current : rest)
      | needle == "" = haystack
      | needle `prefixOf` haystack = replacement ++ go (drop (length needle) haystack)
      | otherwise = current : go rest

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (left : restLeft) (right : restRight) =
  left == right && prefixOf restLeft restRight
