module Compiler.Scenario
  ( CompiledScenario(..)
  , CompiledScenarioTimeline
  , ScenarioDelta(..)
  , compileScenarios
  , emptyScenarioDelta
  , scenarioFactsUpTo
  , scenarioTimelineUpTo
  ) where

import Compiler.AST
import Compiler.Compiler
import Compiler.SymbolTable
import Data.List (foldl')
import qualified Data.Map.Strict as M
import Data.Time.Calendar (Day)
import LegalOntology
import NormativeGenerators
import qualified Patrimony as P
import qualified Data.Set as S

data ScenarioDelta = ScenarioDelta
  { deltaNormFacts :: Norm
  , deltaPatrFacts :: P.PatrimonyState
  , deltaDescriptions :: [String]
  }
  deriving (Eq, Show)

type CompiledScenarioTimeline = M.Map Day ScenarioDelta

data CompiledScenario = CompiledScenario
  { compiledScenarioName :: String
  , compiledScenarioTimeline :: CompiledScenarioTimeline
  }
  deriving (Eq, Show)

compileScenarios :: LawModuleAst -> Either [Diagnostic] [CompiledScenario]
compileScenarios lawModule = do
  symbols <- buildSymbolTable lawModule
  mapM (compileScenario (lawMeta lawModule) symbols) (lawScenarios lawModule)

emptyScenarioDelta :: ScenarioDelta
emptyScenarioDelta =
  ScenarioDelta
    { deltaNormFacts = emptyNorm
    , deltaPatrFacts = P.emptyPatrimony
    , deltaDescriptions = []
    }

scenarioFactsUpTo :: Day -> CompiledScenario -> ScenarioDelta
scenarioFactsUpTo auditDate compiledScenario =
  foldl' mergeScenarioDelta emptyScenarioDelta (map snd (scenarioTimelineUpTo auditDate compiledScenario))

scenarioTimelineUpTo :: Day -> CompiledScenario -> [(Day, ScenarioDelta)]
scenarioTimelineUpTo auditDate compiledScenario =
  M.toAscList (M.filterWithKey (\day _ -> day <= auditDate) (compiledScenarioTimeline compiledScenario))

compileScenario
  :: LawMetaAst
  -> SymbolTable
  -> ScenarioAst
  -> Either [Diagnostic] CompiledScenario
compileScenario meta symbols scenarioAst = do
  entries <- mapM (compileScenarioEntry meta symbols) (scenarioEntries scenarioAst)
  pure $
    CompiledScenario
      { compiledScenarioName = scenarioName scenarioAst
      , compiledScenarioTimeline =
          M.fromListWith mergeScenarioDelta
            [ (day, delta)
            | (day, delta) <- entries
            ]
      }

compileScenarioEntry
  :: LawMetaAst
  -> SymbolTable
  -> ScenarioEntryAst
  -> Either [Diagnostic] (Day, ScenarioDelta)
compileScenarioEntry meta symbols entry = do
  deltas <- mapM (compileScenarioAssertion meta symbols (scenarioDate entry)) (scenarioAssertions entry)
  pure (scenarioDate entry, foldl' mergeScenarioDelta emptyScenarioDelta deltas)

compileScenarioAssertion
  :: LawMetaAst
  -> SymbolTable
  -> Day
  -> ScenarioAssertionAst
  -> Either [Diagnostic] ScenarioDelta
compileScenarioAssertion meta symbols day assertion =
  case assertion of
    ScenarioAct actionAst -> do
      resolved <- resolveAction symbols actionAst
      let fact =
            case actionPolarity actionAst of
              PositiveActionAst ->
                indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToAct resolved))
              NegativeActionAst ->
                indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToCounterAct resolved))
      pure $
        ScenarioDelta
          { deltaNormFacts = S.singleton fact
          , deltaPatrFacts = P.emptyPatrimony
          , deltaDescriptions = ["Act: " ++ renderActionPhrase actionAst]
          }
    ScenarioCounterAct actionAst -> do
      resolved <- resolveAction symbols actionAst
      let fact = indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToCounterAct resolved))
      pure $
        ScenarioDelta
          { deltaNormFacts = S.singleton fact
          , deltaPatrFacts = P.emptyPatrimony
          , deltaDescriptions = ["Counter-act: " ++ renderCounterActionPhrase actionAst]
          }
    ScenarioCondition conditionAst ->
      compileScenarioCondition meta symbols day conditionAst
    ScenarioEvent eventAst ->
      let fact =
            indexedGen (lawAuthorityAst meta) day $
              GEvent $
                case eventAst of
                  HumanEventAst description -> HumanAct description
                  NaturalEventAst description -> NaturalFact description
      in pure $
          ScenarioDelta
            { deltaNormFacts = S.singleton fact
            , deltaPatrFacts = P.emptyPatrimony
            , deltaDescriptions = [renderEventLabel eventAst]
            }

compileScenarioCondition
  :: LawMetaAst
  -> SymbolTable
  -> Day
  -> ConditionAst
  -> Either [Diagnostic] ScenarioDelta
compileScenarioCondition meta symbols day conditionAst =
  case conditionAst of
    InstitutionalConditionAst _ -> do
      resolvedCondition <- resolveCondition symbols conditionAst
      case resolvedCondition of
        ResolvedOwnershipCondition owner obj ->
          pure $
            ScenarioDelta
              { deltaNormFacts =
                  S.singleton
                    (indexedGen (lawAuthorityAst meta) day (GEvent (HumanAct ("ownership:" ++ pName owner ++ ":" ++ oName obj))))
              , deltaPatrFacts = S.singleton (P.Owned obj)
              , deltaDescriptions = ["Assertion: " ++ pName owner ++ " owns " ++ oName obj]
              }
        ResolvedCapabilityCondition capability ->
          pure $
            ScenarioDelta
              { deltaNormFacts =
                  S.singleton
                    (indexedGen (lawAuthorityAst meta) day (GEvent (HumanAct ("capability:" ++ show capability))))
              , deltaPatrFacts = S.singleton (P.Capability (capabilityToken capability))
              , deltaDescriptions = ["Assertion: authority " ++ show capability ++ " is present"]
              }
        ResolvedAssetCondition assetName ->
          pure $
            ScenarioDelta
              { deltaNormFacts = emptyNorm
              , deltaPatrFacts = S.singleton (P.Asset assetName)
              , deltaDescriptions = ["Assertion: asset " ++ assetName ++ " is present"]
              }
        ResolvedLiabilityCondition liabilityName ->
          pure $
            ScenarioDelta
              { deltaNormFacts = emptyNorm
              , deltaPatrFacts = S.singleton (P.Liability liabilityName)
              , deltaDescriptions = ["Assertion: liability " ++ liabilityName ++ " is present"]
              }
        ResolvedActionCondition _ ->
          Left [Diagnostic "scenario" "unexpected action condition in institutional assertion"]
    ActionConditionAst actionAst -> do
      resolved <- resolveAction symbols actionAst
      let fact =
            case actionPolarity actionAst of
              PositiveActionAst ->
                indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToAct resolved))
              NegativeActionAst ->
                indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToCounterAct resolved))
      pure $
        ScenarioDelta
          { deltaNormFacts = S.singleton fact
          , deltaPatrFacts = P.emptyPatrimony
          , deltaDescriptions = ["Assertion: " ++ renderActionPhrase actionAst]
          }

mergeScenarioDelta :: ScenarioDelta -> ScenarioDelta -> ScenarioDelta
mergeScenarioDelta left right =
  ScenarioDelta
    { deltaNormFacts = unionNorm (deltaNormFacts left) (deltaNormFacts right)
    , deltaPatrFacts = S.union (deltaPatrFacts left) (deltaPatrFacts right)
    , deltaDescriptions = deltaDescriptions left ++ deltaDescriptions right
    }

renderActionPhrase :: ActionPhraseAst -> String
renderActionPhrase actionAst =
  actionActorName actionAst
    ++ " "
    ++ actionVerb actionAst
    ++ " "
    ++ actionObjectName actionAst
    ++ maybe "" (" to " ++) (actionTargetName actionAst)

renderCounterActionPhrase :: ActionPhraseAst -> String
renderCounterActionPhrase actionAst =
  actionActorName actionAst
    ++ " fails to "
    ++ actionVerb actionAst
    ++ " "
    ++ actionObjectName actionAst
    ++ maybe "" (" to " ++) (actionTargetName actionAst)

renderEventLabel :: LegalEventAst -> String
renderEventLabel eventAst =
  case eventAst of
    HumanEventAst description -> "Event: " ++ description
    NaturalEventAst description -> "Natural event: " ++ description

capabilityToken :: CapabilityIndex -> String
capabilityToken capability =
  case capability of
    BaseAuthority -> "baseauthority"
    PrivatePower -> "private"
    LegislativePower -> "legislative"
    JudicialPower -> "judicial"
    AdministrativePower -> "administrative"
    ConstitutionalPower -> "constitutional"
