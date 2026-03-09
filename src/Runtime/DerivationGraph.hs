{-# LANGUAGE LambdaCase #-}

module Runtime.DerivationGraph
  ( DerivationGraph(..)
  , DerivationNode(..)
  , DerivationEdge(..)
  , NodeProvenance(..)
  , buildDerivationGraph
  , exportDerivationGraphJson
  , exportDerivationGraphDot
  , exportDerivationGraphMermaid
  ) where

import Capability (prettyCapability)
import Compiler.Compiler (CompiledLawModule(..), DisplayVerbMap(..), RuleSpec(..))
import Data.Aeson (Value, object, (.=), encode)
import Data.Aeson.Key (fromString)
import qualified Data.Map.Strict as M
import Data.ByteString.Lazy (ByteString)
import Data.List (nub)
import Data.Time.Calendar (Day, toGregorian, fromGregorian)
import qualified Data.Set as S
import NormativeGenerators (IndexedGen(..))
import qualified Patrimony as P
import Pretty.PrettyNorm (prettyIndexedGenWithDisplay)
import Pretty.PrettyReport (prettyCondition)
import Runtime.Audit (AuditResult(..))
import Runtime.Provenance

epochDate :: Day
epochDate = fromGregorian 1 1 1

-- | Provenance of a generator node: seed (scenario), derived (rule output), or patrimony.
data NodeProvenance
  = SeedNorm
  | DerivedNorm
  | PatrimonyFact
  deriving (Eq, Show)

-- | A node in the derivation graph: either a generator (fact) or a rule application.
data DerivationNode
  = GeneratorNode String String NodeProvenance
  | RuleNode String String
  deriving (Eq, Show)

-- | An edge from source node ID to target node ID.
data DerivationEdge = DerivationEdge
  { edgeFrom :: String
  , edgeTo :: String
  }
  deriving (Eq, Show)

-- | Structured derivation graph: nodes and edges.
data DerivationGraph = DerivationGraph
  { graphNodes :: [(String, DerivationNode)]
  , graphEdges :: [DerivationEdge]
  }
  deriving (Eq, Show)

-- | Build a derivation graph from a compiled module and audit result.
-- Uses DisplayVerbMap for canonical labels and rule lookup for condition annotations.
buildDerivationGraph :: CompiledLawModule -> AuditResult -> DerivationGraph
buildDerivationGraph compiled result =
  DerivationGraph
    { graphNodes = nodes
    , graphEdges = edges
    }
  where
    displayMap = compiledDisplayVerbMap compiled
    ruleSpecs = compiledRules compiled
    seeds = auditScenarioSeeds result
    firings = auditRuleFirings result
    seedFactIds = S.fromList [factRefToGenId fact | seed <- seeds, fact <- seedFacts seed]

    -- Canonical label for IndexedGen
    normLabel ig = prettyIndexedGenWithDisplay displayMap ig

    -- Short label for patrimony facts
    patrimonyLabel p = case p of
      P.Asset n -> "asset(" ++ n ++ ")"
      P.Liability n -> "liability(" ++ n ++ ")"
      P.Collateral n -> "collateral(" ++ n ++ ")"
      P.Certification n -> "certification(" ++ n ++ ")"
      P.ApprovedContractor n -> "approved contractor(" ++ n ++ ")"
      P.Capability n -> "capability(" ++ n ++ ")"
      P.Owned obj -> "owned(" ++ show obj ++ ")"
      P.NumericFact n v -> "numeric(" ++ n ++ "=" ++ show v ++ ")"
      P.DateFact n d -> "date(" ++ n ++ "=" ++ show d ++ ")"

    -- Rule label with condition and epoch-date handling
    ruleLabel fire =
      let name = ruleName fire
          cond = maybe "" (\r -> " | " ++ prettyCondition (ruleSpecCondition r)) (lookupRule name)
          dayNote = if witnessDay fire == epochDate then " [institutional fact]" else " [" ++ formatDay (witnessDay fire) ++ "]"
      in name ++ dayNote ++ cond

    lookupRule name = case filter (\r -> ruleSpecName r == name) ruleSpecs of
      r : _ -> Just r
      [] -> Nothing

    ruleName fire = case ruleOrigin fire of
      DslRule n -> n
      BuiltInRule n -> n

    -- Seed nodes (from scenario)
    seedGenNodes =
      [ (factRefToGenId fact, mkGenNode fact SeedNorm)
      | seed <- seeds
      , fact <- seedFacts seed
      ]

    -- Witness nodes (may be seed or derived)
    firingGenNodes =
      [ (factRefToGenId fact, mkGenNode fact (provForFact fact))
      | fire <- firings
      , fact <- witnessFacts fire
      ]

    provForFact fact = case fact of
      PatrFact _ -> PatrimonyFact
      NormFact _ -> if factRefToGenId fact `S.member` seedFactIds then SeedNorm else DerivedNorm

    -- Consequent nodes (always derived)
    consequentGenNodes =
      [ (genId (consequent fire), GeneratorNode (genId (consequent fire)) (normLabel (consequent fire)) DerivedNorm)
      | fire <- firings
      ]

    mkGenNode fact prov = case fact of
      NormFact ig -> GeneratorNode (factRefToGenId fact) (normLabel ig) prov
      PatrFact p -> GeneratorNode (factRefToGenId fact) (patrimonyLabel p) PatrimonyFact

    -- Rule nodes
    ruleNodes =
      [ (ruleNodeId fire i, RuleNode (ruleNodeId fire i) (ruleLabel fire))
      | (fire, i) <- zip firings [0 :: Int ..]
      ]

    -- Deduplicate nodes by ID (first element of pair)
    allNodePairs = seedGenNodes ++ firingGenNodes ++ consequentGenNodes ++ ruleNodes
    nodes = M.toList (M.fromList allNodePairs)

    -- Edges: witness -> rule, rule -> consequent
    firingEdges =
      [ (fire, i)
      | (fire, i) <- zip firings [0 :: Int ..]
      ]
    edges =
      nub
        [ DerivationEdge (factRefToGenId fact) (ruleNodeId fire i)
        | (fire, i) <- firingEdges
        , fact <- witnessFacts fire
        ]
        ++
        [ DerivationEdge (ruleNodeId fire i) (genId (consequent fire))
        | (fire, i) <- firingEdges
        ]

genId :: IndexedGen -> String
genId ig = "gen-" ++ sanitize (show ig)

factRefToGenId :: FactRef -> String
factRefToGenId = \case
  NormFact ig -> genId ig
  PatrFact p -> "patr-" ++ sanitize (show p)

ruleNodeId :: RuleFire -> Int -> String
ruleNodeId fire i =
  "rule-" ++ sanitize (show (ruleOrigin fire)) ++ "-" ++ formatDay (witnessDay fire) ++ "-" ++ show i

sanitize :: String -> String
sanitize = map (\c -> if c `elem` " \t\n\"'\\<>" then '_' else c)

formatDay :: Day -> String
formatDay day =
  let (y, m, d) = toGregorian day
  in show y ++ "-" ++ pad 2 m ++ "-" ++ pad 2 d
  where
    pad w n = reverse (take w (reverse (show n) ++ repeat '0'))

-- | Export derivation graph as JSON.
exportDerivationGraphJson :: DerivationGraph -> ByteString
exportDerivationGraphJson graph =
  encode $
    object
      [ fromString "nodes" .= map jsonNode (graphNodes graph)
      , fromString "edges" .= map jsonEdge (graphEdges graph)
      ]
  where
    jsonNode (nodeId, node) =
      object
        [ fromString "id" .= nodeId
        , fromString "type" .= nodeType node
        , fromString "label" .= nodeLabel node
        , fromString "provenance" .= nodeProvenance node
        ]
    nodeType = \case
      GeneratorNode _ _ _ -> ("generator" :: String)
      RuleNode _ _ -> ("rule" :: String)
    nodeLabel = \case
      GeneratorNode _ label _ -> label
      RuleNode _ label -> label
    nodeProvenance = \case
      GeneratorNode _ _ prov -> show prov
      RuleNode _ _ -> ("rule" :: String)
    jsonEdge e =
      object
        [ fromString "from" .= edgeFrom e
        , fromString "to" .= edgeTo e
        ]

-- | Export derivation graph as Graphviz DOT.
exportDerivationGraphDot :: DerivationGraph -> String
exportDerivationGraphDot graph =
  unlines
    [ "digraph Derivation {"
    , "  rankdir=LR;"
    , "  node [shape=box];"
    , "  node [fontsize=10];"
    ]
    ++ concat (concatMap dotNode (graphNodes graph))
    ++ concat (concatMap dotEdge (graphEdges graph))
    ++ "}"
  where
    dotNode (nodeId, node) =
      [ "  \"" ++ escape nodeId ++ "\" [label=\"" ++ escape (nodeLabel node) ++ "\"" ++ dotStyle node ++ "];"
      ]
    nodeLabel = \case
      GeneratorNode _ label _ -> label
      RuleNode _ label -> label
    dotStyle = \case
      GeneratorNode _ _ SeedNorm -> ", style=filled, fillcolor=lightblue"
      GeneratorNode _ _ DerivedNorm -> ", style=filled, fillcolor=lightgreen"
      GeneratorNode _ _ PatrimonyFact -> ", style=filled, fillcolor=lightyellow"
      RuleNode _ _ -> ", style=filled, fillcolor=lavender"
    dotEdge e =
      [ "  \"" ++ escape (edgeFrom e) ++ "\" -> \"" ++ escape (edgeTo e) ++ "\";"
      ]
    escape = concatMap (\c -> if c == '"' then "\\\"" else [c])

-- | Export derivation graph as Mermaid flowchart.
exportDerivationGraphMermaid :: DerivationGraph -> String
exportDerivationGraphMermaid graph =
  unlines
    [ "flowchart LR"
    ]
    ++ concat (concatMap mermaidNode (graphNodes graph))
    ++ concat (concatMap mermaidEdge (graphEdges graph))
  where
    idMap = M.fromList (zip (map fst (graphNodes graph)) [0 :: Int ..])
    toMermaidId nodeId = "N" ++ show (idMap M.! nodeId)
    mermaidNode (nodeId, node) =
      [ "  " ++ toMermaidId nodeId ++ "[\"" ++ escape (nodeLabel node) ++ "\"]"
      ]
    nodeLabel = \case
      GeneratorNode _ label _ -> label
      RuleNode _ label -> label
    mermaidEdge e =
      [ "  " ++ toMermaidId (edgeFrom e) ++ " --> " ++ toMermaidId (edgeTo e)
      ]
    escape = concatMap (\c -> if c `elem` "\"[]" then "_" else [c])
