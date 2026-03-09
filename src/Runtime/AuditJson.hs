{-# LANGUAGE LambdaCase #-}

module Runtime.AuditJson
  ( auditResultToJson
  , auditReplayToJson
  ) where

import Compiler.Compiler
import Data.Aeson (Value, object, (.=), encode)
import Data.Aeson.Key (fromString)
import Data.ByteString.Lazy (ByteString)
import Data.Time.Calendar (Day, toGregorian)
import qualified Data.Set as S
import Logic (SystemState(..))
import NormativeGenerators (IndexedGen(..), activeNorms)
import Runtime.Audit (AuditResult(..))
import Runtime.Provenance

-- | Encode an AuditResult as JSON for programmatic analysis.
auditResultToJson :: CompiledLawModule -> AuditResult -> ByteString
auditResultToJson compiled result =
  encode $
    object
      [ fromString "verdict" .= jsonVerdict (complianceVerdict (auditComplianceSummary result))
      , fromString "auditDate" .= formatDay (auditDate result)
      , fromString "scenarioName" .= auditScenarioName result
      , fromString "violations" .= map jsonIndexedGen (violatedNorms (auditComplianceSummary result))
      , fromString "fulfilledNorms" .= map jsonIndexedGen (fulfilledNorms (auditComplianceSummary result))
      , fromString "enforceableNorms" .= map jsonIndexedGen (enforceableNorms (auditComplianceSummary result))
      , fromString "pendingObligations" .= map jsonIndexedGen (pendingObligations (auditComplianceSummary result))
      , fromString "activeProhibitions" .= map jsonIndexedGen (activeProhibitions (auditComplianceSummary result))
      , fromString "ruleFirings" .= map jsonRuleFire (auditRuleFirings result)
      , fromString "timeline" .= map jsonTraceDay (auditDerivationTrace result)
      , fromString "normativeState" .= map jsonIndexedGen (S.toList (activeNorms (normState (auditFinalState result))))
      ]

-- | Encode a scenario replay (list of day + audit result) as JSON.
auditReplayToJson :: CompiledLawModule -> [(Day, AuditResult)] -> ByteString
auditReplayToJson compiled replay =
  encode $
    object
      [ fromString "replay" .= map jsonReplayEntry replay
      ]
  where
    jsonReplayEntry (day, result) =
      object
        [ fromString "date" .= formatDay day
        , fromString "audit" .= jsonAuditSummary result
        ]

jsonAuditSummary :: AuditResult -> Value
jsonAuditSummary result =
  object
    [ fromString "verdict" .= jsonVerdict (complianceVerdict (auditComplianceSummary result))
    , fromString "violations" .= length (violatedNorms (auditComplianceSummary result))
    , fromString "ruleFirings" .= length (auditRuleFirings result)
    ]

jsonVerdict :: Verdict -> String
jsonVerdict = \case
  Compliant -> "compliant"
  NonCompliant -> "non_compliant"

formatDay :: Day -> String
formatDay day =
  let (y, m, d) = toGregorian day
  in show y ++ "-" ++ pad 2 m ++ "-" ++ pad 2 d
  where
    pad w n = reverse (take w (reverse (show n) ++ repeat '0'))

jsonIndexedGen :: IndexedGen -> Value
jsonIndexedGen ig =
  object
    [ fromString "capability" .= show (capIndex ig)
    , fromString "time" .= formatDay (time ig)
    , fromString "generator" .= show (gen ig)
    ]

jsonRuleFire :: RuleFire -> Value
jsonRuleFire fire =
  object
    [ fromString "rule" .= show (ruleOrigin fire)
    , fromString "witnessDay" .= formatDay (witnessDay fire)
    , fromString "consequent" .= jsonIndexedGen (consequent fire)
    , fromString "insertedNew" .= insertedNew fire
    ]

jsonTraceDay :: (Day, [DerivationStep]) -> Value
jsonTraceDay (day, steps) =
  object
    [ fromString "date" .= formatDay day
    , fromString "steps" .= map jsonDerivationStep steps
    ]

jsonDerivationStep :: DerivationStep -> Value
jsonDerivationStep = \case
  SeedStep seed ->
    object
      [ fromString "type" .= ("seed" :: String)
      , fromString "day" .= formatDay (seedDay seed)
      , fromString "text" .= seedText seed
      ]
  RuleStep fire ->
    object
      [ fromString "type" .= ("rule" :: String)
      , fromString "rule" .= show (ruleOrigin fire)
      , fromString "consequent" .= jsonIndexedGen (consequent fire)
      ]
