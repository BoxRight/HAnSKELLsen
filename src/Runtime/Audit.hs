module Runtime.Audit
  ( AuditResult(..)
  , lookupScenario
  , runAudit
  ) where

import Compiler.Compiler
import Compiler.Scenario
import qualified Data.Set as S
import Data.Time.Calendar (Day)
import Logic (SystemState(..), rules, runSystem)
import qualified Patrimony as P
import Runtime.RuleExecution

data AuditResult = AuditResult
  { auditScenarioName :: Maybe String
  , auditDate :: Day
  , auditVisibleTimeline :: [(Day, ScenarioDelta)]
  , auditSeedState :: SystemState
  , auditFinalState :: SystemState
  }
  deriving (Eq, Show)

runAudit
  :: CompiledLawModule
  -> [CompiledScenario]
  -> Maybe String
  -> Day
  -> Either String AuditResult
runAudit compiled scenarios selectedScenarioName selectedAuditDate = do
  selectedScenario <- resolveScenario scenarios selectedScenarioName
  let visibleTimeline =
        maybe [] (scenarioTimelineUpTo selectedAuditDate) selectedScenario
      visibleFacts =
        maybe emptyScenarioDelta (scenarioFactsUpTo selectedAuditDate) selectedScenario
      seedState =
        SystemState
          { normState = S.fromList (compiledFacts compiled) `S.union` deltaNormFacts visibleFacts
          , patrState = P.emptyPatrimony `S.union` deltaPatrFacts visibleFacts
          }
      finalState =
        runSystem (rules ++ ruleSpecsToRules (compiledRules compiled)) seedState
  pure $
    AuditResult
      { auditScenarioName = compiledScenarioName <$> selectedScenario
      , auditDate = selectedAuditDate
      , auditVisibleTimeline = visibleTimeline
      , auditSeedState = seedState
      , auditFinalState = finalState
      }

lookupScenario :: [CompiledScenario] -> String -> Maybe CompiledScenario
lookupScenario scenarios wantedName =
  case filter (\scenario -> compiledScenarioName scenario == wantedName) scenarios of
    scenario : _ -> Just scenario
    [] -> Nothing

resolveScenario
  :: [CompiledScenario]
  -> Maybe String
  -> Either String (Maybe CompiledScenario)
resolveScenario scenarios maybeName =
  case maybeName of
    Nothing -> Right Nothing
    Just name ->
      case lookupScenario scenarios name of
        Just scenario -> Right (Just scenario)
        Nothing -> Left ("unknown scenario `" ++ name ++ "`")
