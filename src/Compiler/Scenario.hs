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
import Data.Time.Calendar (Day, fromGregorian)
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
      let act = resolvedActionToAct resolved
          fact = indexedGen (lawAuthorityAst meta) day (GAct act)
      pure $
        ScenarioDelta
          { deltaNormFacts = S.singleton fact
          , deltaPatrFacts = P.emptyPatrimony
          , deltaDescriptions = ["Act: " ++ renderActionPhrase actionAst]
          }
    ScenarioCounterAct actionAst -> do
      resolved <- resolveCounterAction symbols actionAst
      let fact = indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToCounterAct resolved))
      pure $
        ScenarioDelta
          { deltaNormFacts = S.singleton fact
          , deltaPatrFacts = P.emptyPatrimony
          , deltaDescriptions = ["Counter-act: " ++ renderCounterActionPhrase actionAst]
          }
    ScenarioCondition conditionAst ->
      compileScenarioCondition meta symbols day conditionAst
    ScenarioEvent description ->
      let fact = indexedGen (lawAuthorityAst meta) day (GEvent (HumanAct description))
      in pure $
          ScenarioDelta
            { deltaNormFacts = S.singleton fact
            , deltaPatrFacts = P.emptyPatrimony
            , deltaDescriptions = ["event " ++ description]
            }

compileScenarioCondition
  :: LawMetaAst
  -> SymbolTable
  -> Day
  -> ConditionAst
  -> Either [Diagnostic] ScenarioDelta
compileScenarioCondition meta symbols day conditionAst =
  case conditionAst of
    OwnershipConditionAst partyName objectName -> do
      resolvedCondition <- resolveCondition symbols conditionAst
      case resolvedCondition of
        ResolvedOwnershipCondition _ obj ->
          pure $
            ScenarioDelta
              { deltaNormFacts = S.singleton (indexedGen (lawAuthorityAst meta) day (GEvent (HumanAct ("ownership:" ++ partyName ++ ":" ++ objectName))))
              , deltaPatrFacts = S.singleton (P.Owned obj)
              , deltaDescriptions = ["Assertion: " ++ partyName ++ " owns " ++ objectName]
              }
        _ ->
          Left [Diagnostic "scenario" "unexpected non-ownership condition during ownership compilation"]
    ActionConditionAst actionAst -> do
      resolved <- resolveAction symbols actionAst
      let fact = indexedGen (lawAuthorityAst meta) day (GAct (resolvedActionToAct resolved))
      pure $
        ScenarioDelta
          { deltaNormFacts = S.singleton fact
          , deltaPatrFacts = P.emptyPatrimony
          , deltaDescriptions = ["Assertion: " ++ renderActionPhrase actionAst]
          }

resolveCounterAction :: SymbolTable -> ActionPhraseAst -> Either [Diagnostic] ResolvedAction
resolveCounterAction symbols actionAst = do
  actor <- liftDiag (resolvePartyDecl symbols (actionActorName actionAst))
  objectDecl <- liftDiag (resolveObjectDecl symbols (actionObjectName actionAst))
  targetName <-
    case actionTargetName actionAst of
      Just name -> Right name
      Nothing ->
        Left
          [ Diagnostic "scenario"
              ("missing target for counteract by `" ++ actionActorName actionAst ++ "`")
          ]
  target <- liftDiag (resolvePartyDecl symbols targetName)
  pure $
    ResolvedAction
      { resolvedActionVerb = actionVerb actionAst
      , resolvedActionActor = Person Physical (partyDisplayName actor) Exercise ""
      , resolvedActionObject = Object (objectSubtypeFromKind (objectKind objectDecl)) (actionObjectName actionAst) epoch epoch Nothing
      , resolvedActionTarget = Person Physical (partyDisplayName target) Exercise ""
      }
  where
    epoch = fromGregorian 1 1 1

liftDiag :: Either Diagnostic a -> Either [Diagnostic] a
liftDiag =
  either (Left . (: [])) Right

objectSubtypeFromKind :: ObjectKindAst -> OSubtype
objectSubtypeFromKind kind =
  case kind of
    MovableKind -> ThingSubtype Movable
    NonMovableKind -> ThingSubtype NonMovable
    ExpendableKind -> ThingSubtype Expendable
    MoneyKind -> ThingSubtype Expendable
    ServiceKind -> ServiceSubtype (Performance Nothing)

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
    ++ " fails "
    ++ actionObjectName actionAst
    ++ maybe "" (" to " ++) (actionTargetName actionAst)
