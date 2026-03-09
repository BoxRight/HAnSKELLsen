{-# LANGUAGE LambdaCase #-}

module Runtime.DerivationGraph
  ( DerivationGraph(..)
  , DerivationNode(..)
  , DerivationEdge(..)
  , buildDerivationGraph
  , exportDerivationGraphJson
  , exportDerivationGraphDot
  , exportDerivationGraphMermaid
  ) where

import Compiler.Compiler
import Data.Aeson (Value, object, (.=), encode)
import Data.Aeson.Key (fromString)
import qualified Data.Map.Strict as M
import Data.ByteString.Lazy (ByteString)
import Data.List (nub)
import Data.Time.Calendar (Day, toGregorian)
import qualified Data.Set as S
import NormativeGenerators (IndexedGen(..))
import qualified Patrimony as P
import Runtime.Audit (AuditResult(..))
import Runtime.Provenance

-- | A node in the derivation graph: either a generator (fact) or a rule application.
data DerivationNode
  = GeneratorNode String String
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

-- | Build a derivation graph from an audit result.
-- Seeds become generator nodes; rule firings become rule nodes with edges
-- from witness facts to the rule and from the rule to the consequent.
buildDerivationGraph :: AuditResult -> DerivationGraph
buildDerivationGraph result =
  DerivationGraph
    { graphNodes = nodes
    , graphEdges = edges
    }
  where
    seeds = auditScenarioSeeds result
    firings = auditRuleFirings result

    -- Collect all generator nodes from seeds and rule firings
    seedGenNodes =
      [ (factRefToGenId fact, GeneratorNode (factRefToGenId fact) (show fact))
      | seed <- seeds
      , fact <- seedFacts seed
      ]
    firingGenNodes =
      [ (factRefToGenId fact, GeneratorNode (factRefToGenId fact) (show fact))
      | fire <- firings
      , fact <- witnessFacts fire
      ]
    consequentGenNodes =
      [ (genId (consequent fire), GeneratorNode (genId (consequent fire)) (show (consequent fire)))
      | fire <- firings
      ]

    -- Rule nodes (indexed to ensure uniqueness when same rule fires multiple times)
    ruleNodes =
      [ (ruleNodeId fire i, RuleNode (ruleNodeId fire i) (show (ruleOrigin fire)))
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
        ]
    nodeType = \case
      GeneratorNode _ _ -> ("generator" :: String)
      RuleNode _ _ -> ("rule" :: String)
    nodeLabel = \case
      GeneratorNode _ label -> label
      RuleNode _ label -> label
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
    ]
    ++ concat (concatMap dotNode (graphNodes graph))
    ++ concat (concatMap dotEdge (graphEdges graph))
    ++ "}"
  where
    dotNode (nodeId, node) =
      [ "  \"" ++ escape nodeId ++ "\" [label=\"" ++ escape (nodeLabel node) ++ "\"];"
      ]
    nodeLabel = \case
      GeneratorNode _ label -> label
      RuleNode _ label -> label
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
      GeneratorNode _ label -> label
      RuleNode _ label -> label
    mermaidEdge e =
      [ "  " ++ toMermaidId (edgeFrom e) ++ " --> " ++ toMermaidId (edgeTo e)
      ]
    escape = concatMap (\c -> if c `elem` "\"[]" then "_" else [c])
