{-# LANGUAGE GADTs #-}
{-# LANGUAGE ExistentialQuantification #-}

-- | Quantale evaluation: interprets the compiled program under quantale semantics
-- (multiplication/join) rather than rule-fixpoint semantics. Produces act
-- composition analysis, procedure multiplication, and alternative branches.
--
-- Operates over ALL act generators: procedures, scenarios, rules, and facts.
-- Procedures are optional syntactic hints; the algebra is defined over the full
-- generator set regardless of origin.
module Runtime.QuantaleAnalysis
  ( generateQuantaleReport
  , generateQuantaleReportWith
  , reachabilityReport
  , cyclesReport
  , criticalReport
  , violationPathsReport
  , ActId(..)
  , ActCarrier(..)
  , QuantaleOptions(..)
  , emptyQuantaleOptions
  ) where

import Compiler.AST (LawMetaAst(..), lawNameAst)
import Compiler.Compiler (CompiledLawModule(..), DisplayVerbMap(..), ProcedureIR(..), RuleSpec(..))
import Compiler.Scenario (CompiledScenario(..), ScenarioDelta(..))
import Data.List (foldl', nub, nubBy, sort, sortOn)
import Data.Maybe (isJust)
import qualified Data.Map.Strict as M
import LegalOntology (Act(..), Active, Claim(..), Object, Obligation(..), OSubtype(..), Privilege(..), Prohibition(..), Service(..), Thing(..), pName, oName, oSubtype)
import NormativeGenerators (Generator(..), IndexedGen(..), Norm, emptyNorm, insertGen)
import Quantale (composeGen, joinNorm, kleeneStar, kleeneStarLimited, mulNorm, unitNorm)
import qualified Data.Set as S

-- | Canonical identifier for an act in the composition graph.
-- Identity includes actor, verb, object, and counter/simple status.
newtype ActId = ActId String
  deriving (Eq, Ord, Show)

-- | Normalized act carrier: unique generators with bidirectional lookup.
data ActCarrier = ActCarrier
  { carrierMap :: M.Map ActId IndexedGen
  , carrierDisplayMap :: DisplayVerbMap
  }

-- | Options for quantale analysis and CLI query mode.
data QuantaleOptions = QuantaleOptions
  { qInputPath :: FilePath
  , qReachability :: Maybe String
  , qCycles :: Bool
  , qCritical :: Bool
  , qViolationPaths :: Bool
  }
  deriving (Eq, Show)

emptyQuantaleOptions :: QuantaleOptions
emptyQuantaleOptions =
  QuantaleOptions
    { qInputPath = ""
    , qReachability = Nothing
    , qCycles = False
    , qCritical = False
    , qViolationPaths = False
    }

-- | Max iterations for Kleene closure to prevent runaway growth.
maxClosureIterations :: Int
maxClosureIterations = 15

-- | Generate a quantale analysis report from a compiled law module and scenarios.
-- Collects act generators from procedures, scenarios, rules, and facts.
generateQuantaleReport :: CompiledLawModule -> [CompiledScenario] -> String
generateQuantaleReport compiled scenarios =
  generateQuantaleReportWith compiled scenarios emptyQuantaleOptions

generateQuantaleReportWith :: CompiledLawModule -> [CompiledScenario] -> QuantaleOptions -> String
generateQuantaleReportWith compiled scenarios opts =
  unlines
    [ "Quantale Analysis Report"
    , "======================"
    , ""
    , "Law: " ++ lawNameAst (compiledMetadata compiled)
    , ""
    , actGeneratorsSection carrier
    , actCompositionGraphSection carrier cg
    , procedureMultiplicationSection (carrierDisplayMap carrier) compiled
    , alternativeBranchesSection (carrierDisplayMap carrier) compiled
    , scenarioTracesSection (carrierDisplayMap carrier) scenarios
    , closureSection carrier
    , reachableConsequencesSection carrier cg opts
    , cyclesSection carrier cg opts
    , criticalSection carrier scenarios opts
    , violationPathsSection carrier cg opts
    ]
  where
    carrier = buildActCarrier compiled scenarios
    cg = buildCompositionGraph carrier

-- | Existential wrapper for Act r (heterogeneous act lists from scenarios).
data SomeAct = forall r. SomeAct (Act r)

someActLabel :: DisplayVerbMap -> SomeAct -> String
someActLabel dm (SomeAct a) = actShortLabel dm a

actToActId :: DisplayVerbMap -> SomeAct -> ActId
actToActId dm (SomeAct a) = ActId (actShortLabel dm a)

-- | All act IDs in the carrier.
actIds :: ActCarrier -> [ActId]
actIds carrier = M.keys (carrierMap carrier)

-- | Look up IndexedGen by ActId.
lookupAct :: ActCarrier -> ActId -> Maybe IndexedGen
lookupAct carrier aid = M.lookup aid (carrierMap carrier)

-- | Resolve string to ActId by exact match. Returns Nothing if not found.
resolveActId :: ActCarrier -> String -> Maybe ActId
resolveActId carrier s =
  let aid = ActId s
  in if M.member aid (carrierMap carrier) then Just aid else Nothing

-- | Semantic composition graph: edges only when composeGen succeeds.
data CompositionGraph = CompositionGraph
  { cgForward :: M.Map ActId [ActId]
  , cgBackward :: M.Map ActId [ActId]
  }

-- | Build full algebraic composition graph from all pairs in the carrier.
buildCompositionGraph :: ActCarrier -> CompositionGraph
buildCompositionGraph carrier =
  CompositionGraph
    { cgForward = forward
    , cgBackward = reverseGraph forward
    }
  where
    aids = actIds carrier
    forward =
      M.fromListWith (++) $
        [ (aidA, [aidB])
        | aidA <- aids
        , aidB <- aids
        , aidA /= aidB
        , Just igA <- [lookupAct carrier aidA]
        , Just igB <- [lookupAct carrier aidB]
        , isJust (composeGen (gen igA) (gen igB))
        ]
    reverseGraph adj =
      M.fromListWith (++) $
        concatMap (\(a, bs) -> [(b, [a]) | b <- bs]) (M.assocs adj)

-- | BFS: all acts reachable from the given act via composition edges.
reachableFrom :: M.Map ActId [ActId] -> ActId -> S.Set ActId
reachableFrom adj start =
  go S.empty (S.singleton start)
  where
    go visited frontier
      | S.null frontier = visited
      | otherwise =
          let (x, rest) = (S.findMin frontier, S.deleteMin frontier)
              visited' = S.insert x visited
              succs = S.fromList (M.findWithDefault [] x adj)
              newSuccs = succs S.\\ visited'
              frontier' = S.union rest (newSuccs S.\\ rest)
          in go visited' frontier'

-- | Kosaraju's algorithm: strongly connected components.
stronglyConnectedComponents :: M.Map ActId [ActId] -> [[ActId]]
stronglyConnectedComponents adj =
  let rev = M.fromListWith (++) $ concatMap (\(a, bs) -> [(b, [a]) | b <- bs]) (M.assocs adj)
      allNodes = S.toList (S.fromList (M.keys adj) `S.union` S.fromList (concat (M.elems adj)))
      (_, order) = dfsPostOrder adj allNodes
      components = dfsCollect rev (reverse order)
  in components

dfsPostOrder :: M.Map ActId [ActId] -> [ActId] -> (S.Set ActId, [ActId])
dfsPostOrder adj nodes =
  foldl'
    (\(visited, order) n ->
      if n `S.member` visited then (visited, order)
      else
        let (v', o') = dfsVisit adj n visited []
        in (v', o' ++ order))
    (S.empty, [])
    nodes

dfsVisit :: M.Map ActId [ActId] -> ActId -> S.Set ActId -> [ActId] -> (S.Set ActId, [ActId])
dfsVisit adj n visited order =
  let visited' = S.insert n visited
      succs = M.findWithDefault [] n adj
      (visited'', order') = foldl'
        (\(v, o) s ->
          if s `S.member` v then (v, o)
          else let (v', o') = dfsVisit adj s v o in (v', o'))
        (visited', order)
        succs
  in (visited'', n : order')

dfsCollect :: M.Map ActId [ActId] -> [ActId] -> [[ActId]]
dfsCollect rev order =
  fst $
    foldl'
      (\(collected, visited) n ->
        if n `S.member` visited then (collected, visited)
        else
          let comp = dfsCollectVisit rev n S.empty
              visited' = S.union visited comp
          in (S.toList comp : collected, visited'))
      ([], S.empty)
      order

dfsCollectVisit :: M.Map ActId [ActId] -> ActId -> S.Set ActId -> S.Set ActId
dfsCollectVisit rev n acc =
  let acc' = S.insert n acc
      preds = M.findWithDefault [] n rev
      reachable = foldl'
        (\a p ->
          if p `S.member` a then a
          else S.union a (dfsCollectVisit rev p a))
        acc'
        preds
  in reachable

-- | Counter-acts in the carrier (GAct Counter).
counterActIds :: ActCarrier -> S.Set ActId
counterActIds carrier =
  S.fromList
    [ aid
    | (aid, ig) <- M.assocs (carrierMap carrier)
    , case gen ig of
        GAct (Counter _ _ _) -> True
        _ -> False
    ]

-- | BFS backward from counter-acts: acts that can precede each counter-act.
violationPredecessors :: CompositionGraph -> S.Set ActId -> M.Map ActId (S.Set ActId)
violationPredecessors cg counterActs =
  M.fromList
    [ (aid, reachableFrom (cgBackward cg) aid)
    | aid <- S.toList counterActs
    ]

-- | Count how many scenario traces each act appears in.
criticalActFrequencies :: ActCarrier -> [CompiledScenario] -> [(ActId, Int)]
criticalActFrequencies carrier scenarios =
  reverse (sortOn snd (M.assocs freqMap))
  where
    freqMap =
      M.fromListWith (+)
        [ (aid, 1)
        | sc <- scenarios
        , ig <- concatMap (S.toList . deltaNormFacts . snd) (M.toAscList (compiledScenarioTimeline sc))
        , GAct a <- [gen ig]
        , let aid = actToActId (carrierDisplayMap carrier) (SomeAct a)
        , M.member aid (carrierMap carrier)
        ]

-- | Bounded traces up to depth k from given starts.
boundedTraces :: Int -> M.Map ActId [ActId] -> [ActId] -> [[ActId]]
boundedTraces maxDepth adj starts =
  nub $ go 0 (map (\s -> [s]) starts)
  where
    go d paths
      | d >= maxDepth = paths
      | null paths = []
      | otherwise =
          let extensions =
                [ p ++ [s]
                | p <- paths
                , length p <= maxDepth
                , s <- M.findWithDefault [] (last p) adj
                ]
          in paths ++ go (d + 1) extensions

buildActCarrier :: CompiledLawModule -> [CompiledScenario] -> ActCarrier
buildActCarrier compiled scenarios =
  ActCarrier
    { carrierMap = M.fromList [(actToActId dm (SomeAct a), ig) | ig <- S.toList norm, GAct a <- [gen ig]]
    , carrierDisplayMap = dm
    }
  where
    dm = compiledDisplayVerbMap compiled
    norm = collectAllActGeneratorsNorm compiled scenarios

-- | Collect all act generators (raw Norm). Deduplicates by generator content.
collectAllActGeneratorsNorm :: CompiledLawModule -> [CompiledScenario] -> Norm
collectAllActGeneratorsNorm compiled scenarios =
  foldr insertGen emptyNorm (dedupByGen allActs)
  where
    meta = compiledMetadata compiled
    fromProcedures =
      [ actToIndexedGen branch meta
      | proc <- compiledProcedures compiled
      , branch <- procedureIrBranches proc
      ]
    fromFacts =
      [ ig'
      | ig <- compiledFacts compiled
      , Just ig' <- [generatorToGAct ig]
      ]
    fromRules =
      [ ig'
      | ig <- map ruleSpecConsequent (compiledRules compiled)
      , Just ig' <- [generatorToGAct ig]
      ]
    fromScenarios =
      [ ig
      | scenario <- scenarios
      , (_, delta) <- M.toAscList (compiledScenarioTimeline scenario)
      , ig <- S.toList (deltaNormFacts delta)
      , case gen ig of
          GAct _ -> True
          _ -> False
      ]
    allActs = fromProcedures ++ fromFacts ++ fromRules ++ fromScenarios

-- | Deduplicate IndexedGen by generator content. Keeps first occurrence per unique GAct.
dedupByGen :: [IndexedGen] -> [IndexedGen]
dedupByGen = go S.empty
  where
    go _ [] = []
    go seen (ig : rest) =
      let g = gen ig
      in if g `S.member` seen then go seen rest else ig : go (S.insert g seen) rest

generatorToGAct :: IndexedGen -> Maybe IndexedGen
generatorToGAct (IndexedGen cap t g) =
  case g of
    GAct _ -> Just (IndexedGen cap t g)
    GObligation (Obligation a) -> Just (IndexedGen cap t (GAct a))
    GClaim (Claim a) -> Just (IndexedGen cap t (GAct a))
    GPrivilege (Privilege a) -> Just (IndexedGen cap t (GAct a))
    GProhibition (Prohibition a) -> Just (IndexedGen cap t (GAct a))
    Overridden g' -> generatorToGAct (IndexedGen cap t g')
    _ -> Nothing

actCompositionGraphSection :: ActCarrier -> CompositionGraph -> String
actCompositionGraphSection carrier cg =
  case compositionEdges of
    [] -> "Act composition graph: (no sequential compositions)"
    _ ->
      unlines
        ( "Act composition graph:"
        : ""
        : map (\(a, b) -> "  " ++ unActId a ++ " → " ++ unActId b) compositionEdges
        )
  where
    unActId (ActId s) = s
    compositionEdges =
      [ (aidA, aidB)
      | (aidA, succs) <- M.assocs (cgForward cg)
      , aidB <- succs
      ]

scenarioTemporalEdges :: [CompiledScenario] -> [(SomeAct, SomeAct)]
scenarioTemporalEdges scenarios =
  concatMap (consecutivePairs . scenarioActsInOrder) scenarios
  where
    scenarioActsInOrder scenario =
      concatMap (extractGActs . deltaNormFacts . snd)
        (M.toAscList (compiledScenarioTimeline scenario))
    extractGActs norm =
      [ SomeAct act | IndexedGen _ _ (GAct act) <- S.toList norm ]
    consecutivePairs acts =
      case acts of
        a : b : rest -> (a, b) : consecutivePairs (b : rest)
        _ -> []

seqToList :: Act r -> [Act r]
seqToList Id = []
seqToList (Seq xs) = concatMap seqToList xs
seqToList x = [x]

-- | Base verb from object subtype (ontology structure). Must match Compiler.buildDisplayVerbMap
-- keys for DisplayVerbMap lookup.
baseVerbForObject :: Object -> String
baseVerbForObject obj =
  case oSubtype obj of
    ThingSubtype Expendable -> "transfer"
    ThingSubtype _ -> "deliver"
    ServiceSubtype (Performance (Just _)) -> "deliver"
    ServiceSubtype (Performance Nothing) -> "perform"
    ServiceSubtype (Omission (Just _)) -> "refrain from interfering with"
    ServiceSubtype (Omission Nothing) -> "refrain from"

-- | Verb for act label: display override if present, else base verb from ontology.
-- For compact labels we use the first word when base is multi-word (e.g. "refrain" from "refrain from").
verbForObject :: DisplayVerbMap -> Object -> String
verbForObject (DisplayVerbMap m) obj =
  let base = baseVerbForObject obj
      display = M.lookup (oName obj, base) m
  in case display of
    Just v -> takeWhile (/= ' ') v  -- "install" or "pay" from display
    Nothing -> takeWhile (/= ' ') base  -- "transfer", "deliver", "perform", "refrain"

actShortLabel :: DisplayVerbMap -> Act r -> String
actShortLabel dm act =
  case act of
    Simple actor obj _ -> pName actor ++ "_" ++ verbForObject dm obj ++ "_" ++ oName obj
    Counter actor obj _ -> pName actor ++ "_counter_" ++ verbForObject dm obj ++ "_" ++ oName obj
    Seq xs -> intercalate "_then_" (map (actShortLabel dm) (filter (/= Id) xs))
    Par xs -> intercalate "_or_" (map (actShortLabel dm) (filter (/= Id) (S.toList xs)))
    Id -> "id"

intercalate :: String -> [String] -> String
intercalate _ [] = ""
intercalate _ [x] = x
intercalate sep (x : xs) = x ++ sep ++ intercalate sep xs

procedureMultiplicationSection :: DisplayVerbMap -> CompiledLawModule -> String
procedureMultiplicationSection dm compiled =
  case compiledProcedures compiled of
    [] -> "Procedure multiplication: (no procedures)"
    procs ->
      unlines
        ( "Procedure multiplication:"
        : ""
        : concatMap (formatProcedure dm) procs
        )
  where
    formatProcedure dm proc =
      case procedureIrBranches proc of
        [branch] ->
          [ "  " ++ procedureIrName proc ++ " = " ++ actShortLabel dm branch
          ]
        branches ->
          [ "  " ++ procedureIrName proc ++ " = " ++ intercalate " ∨ " (map (actShortLabel dm) branches)
          ]

alternativeBranchesSection :: DisplayVerbMap -> CompiledLawModule -> String
alternativeBranchesSection dm compiled =
  case alternativeProcs of
    [] -> "Alternative branches: (none)"
    procs ->
      unlines
        ( "Alternative branches:"
        : ""
        : concatMap (formatAlternative dm) procs
        )
  where
    alternativeProcs =
      filter (\p -> length (procedureIrBranches p) > 1) (compiledProcedures compiled)
    formatAlternative dm proc =
      [ "  " ++ procedureIrName proc ++ ":"
      ]
        ++ map
          (\b -> "    ∨ " ++ actShortLabel dm b)
          (procedureIrBranches proc)

actGeneratorsSection :: ActCarrier -> String
actGeneratorsSection carrier
  | M.null (carrierMap carrier) = "Act generators: (none)"
  | otherwise =
      unlines
        ( "Act generators:"
        : ""
        : [ "  " ++ unActId aid
          | aid <- sort (actIds carrier)
          ]
        )
  where
    unActId (ActId s) = s

scenarioTracesSection :: DisplayVerbMap -> [CompiledScenario] -> String
scenarioTracesSection dm scenarios =
  case traces of
    [] -> "Scenario temporal traces: (none)"
    _ ->
      unlines
        ( "Scenario temporal traces:"
        : ""
        : concatMap (formatTrace dm) traces
        )
  where
    traces =
      [ (compiledScenarioName sc, scenarioActsInOrder sc)
      | sc <- scenarios
      , not (null (scenarioActsInOrder sc))
      ]
    scenarioActsInOrder sc =
      concatMap (extractGActs . deltaNormFacts . snd)
        (M.toAscList (compiledScenarioTimeline sc))
    extractGActs norm =
      [ SomeAct act | IndexedGen _ _ (GAct act) <- S.toList norm ]
    formatTrace dm (name, acts) =
      [ "  " ++ name ++ ":"
      , "    " ++ intercalate " · " (map (someActLabel dm) acts)
      ]

closureSection :: ActCarrier -> String
closureSection carrier
  | M.null (carrierMap carrier) = "Closure (kleeneStar): (no act generators)"
  | otherwise =
      unlines
        [ "Closure (kleeneStar):"
        , ""
        , "  |act generators| = " ++ show (M.size (carrierMap carrier))
        , "  |closure| = " ++ show (S.size closure)
        , if hitLimit then "  (iteration limit " ++ show maxClosureIterations ++ " reached)" else ""
        ]
  where
    actNorm = S.fromList (M.elems (carrierMap carrier))
    (closure, hitLimit) = kleeneStarLimited maxClosureIterations actNorm

unActIdStr :: ActId -> String
unActIdStr (ActId s) = s

reachableConsequencesSection :: ActCarrier -> CompositionGraph -> QuantaleOptions -> String
reachableConsequencesSection carrier cg opts =
  case qReachability opts of
    Nothing ->
      case keyActs of
        [] -> ""
        acts ->
          unlines
            ( "Reachable consequences of key acts:"
            : ""
            : concatMap (formatReachability carrier cg) acts
            )
    Just label ->
      case resolveActId carrier label of
        Nothing -> "Reachable from " ++ label ++ ": (act not found)\n"
        Just aid ->
          unlines $
            ("Reachable from " ++ label ++ ":") : "" : formatReachability carrier cg aid
  where
    keyActs = take 5 (actIds carrier)
    formatReachability car cgr aid =
      [ "  " ++ unActIdStr aid ++ ":"
      , "    " ++ unwords (map unActIdStr (sort (S.toList (reachableFrom (cgForward cgr) aid S.\\ S.singleton aid))))
      ]

cyclesSection :: ActCarrier -> CompositionGraph -> QuantaleOptions -> String
cyclesSection _ cg _ =
  case cycles of
    [] -> "Detected institutional cycles: (none)\n"
    _ ->
      unlines
        ( "Detected institutional cycles:"
        : ""
        : concatMap formatCycle cycles
        )
  where
    cycles = filter ((> 1) . length) (stronglyConnectedComponents (cgForward cg))
    formatCycle comp =
      [ "  Cycle: " ++ unwords (map unActIdStr (sort comp))
      ]

criticalSection :: ActCarrier -> [CompiledScenario] -> QuantaleOptions -> String
criticalSection carrier scenarios _ =
  case critical of
    [] -> "Critical transition points: (none)\n"
    _ ->
      unlines
        ( "Critical transition points:"
        : ""
        : [ "  " ++ unActIdStr aid ++ " (in " ++ show n ++ " scenario traces)"
          | (aid, n) <- take 10 critical
          ]
        )
  where
    critical = criticalActFrequencies carrier scenarios

violationPathsSection :: ActCarrier -> CompositionGraph -> QuantaleOptions -> String
violationPathsSection carrier cg _ =
  if S.null counterActs
    then "Paths leading to violations: (no counter-acts in carrier)\n"
    else
      unlines
        ( "Paths leading to violations:"
        : ""
        : concatMap formatViolPath (M.assocs preds)
        )
  where
    counterActs = counterActIds carrier
    preds = violationPredecessors cg counterActs
    formatViolPath (aid, predSet) =
      [ "  " ++ unActIdStr aid ++ " (counter-act):"
      , "    Preceded by: " ++ unwords (map unActIdStr (sort (S.toList (predSet S.\\ S.singleton aid))))
      ]

-- | Standalone report: reachability from a given act.
reachabilityReport :: CompiledLawModule -> [CompiledScenario] -> String -> String
reachabilityReport compiled scenarios label =
  case resolveActId carrier label of
    Nothing ->
      "Act not found: " ++ label ++ "\n\nAvailable acts:\n"
        ++ unlines (map (("  " ++) . unActIdStr) (sort (actIds carrier)))
    Just aid ->
      unlines
        [ "Reachable from " ++ label ++ ":"
        , ""
        , unwords (map unActIdStr (sort (S.toList (reachableFrom (cgForward cg) aid S.\\ S.singleton aid))))
        ]
  where
    carrier = buildActCarrier compiled scenarios
    cg = buildCompositionGraph carrier

-- | Standalone report: detected cycles.
cyclesReport :: CompiledLawModule -> [CompiledScenario] -> String
cyclesReport compiled scenarios =
  case cycles of
    [] -> "Detected institutional cycles: (none)"
    _ ->
      unlines
        ( "Detected institutional cycles:"
        : ""
        : concatMap formatCycle cycles
        )
  where
    carrier = buildActCarrier compiled scenarios
    cg = buildCompositionGraph carrier
    cycles = filter ((> 1) . length) (stronglyConnectedComponents (cgForward cg))
    formatCycle comp = ["  Cycle: " ++ unwords (map unActIdStr (sort comp))]

-- | Standalone report: critical acts.
criticalReport :: CompiledLawModule -> [CompiledScenario] -> String
criticalReport compiled scenarios =
  case critical of
    [] -> "Critical transition points: (none)"
    _ ->
      unlines
        ( "Critical transition points:"
        : ""
        : [ "  " ++ unActIdStr aid ++ " (in " ++ show n ++ " scenario traces)"
          | (aid, n) <- critical
          ]
        )
  where
    carrier = buildActCarrier compiled scenarios
    critical = criticalActFrequencies carrier scenarios

-- | Standalone report: violation paths.
violationPathsReport :: CompiledLawModule -> [CompiledScenario] -> String
violationPathsReport compiled scenarios =
  case S.toList counterActs of
    [] -> "Paths leading to violations: (no counter-acts in carrier)"
    acts ->
      unlines
        ( "Paths leading to violations:"
        : ""
        : concatMap formatViolPath (M.assocs preds)
        )
  where
    carrier = buildActCarrier compiled scenarios
    cg = buildCompositionGraph carrier
    counterActs = counterActIds carrier
    preds = violationPredecessors cg counterActs
    formatViolPath (aid, predSet) =
      [ "  " ++ unActIdStr aid ++ " (counter-act):"
      , "    Preceded by: " ++ unwords (map unActIdStr (sort (S.toList (predSet S.\\ S.singleton aid))))
      ]

actToIndexedGen :: Act Active -> LawMetaAst -> IndexedGen
actToIndexedGen act meta =
  IndexedGen
    (lawAuthorityAst meta)
    (lawEnactedAst meta)
    (GAct act)