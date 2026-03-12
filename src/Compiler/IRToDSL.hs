{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}

module Compiler.IRToDSL
  ( irToDSL
  , irToDSLWithWarnings
  , IrDocument(..)
  ) where

import Data.Aeson
import Data.Aeson.Key (fromString, toString)
import Data.Aeson.Types (Parser)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.List (intercalate, sort, sortBy, nub)
import Data.Char (toUpper, toLower, isAlphaNum)
import Data.Maybe (mapMaybe, fromMaybe, catMaybes)

-- | Parse a JSON object as a Map, silently skipping any entries whose value
-- is not a JSON object (e.g. `_comment: "..."`).  Returns a Parser so the
-- caller can use @.!=@ and friends.
parseMapFiltered :: FromJSON v => Value -> Parser (M.Map String v)
parseMapFiltered = withObject "Map" $ \km -> do
  let pairs = [(toString k, v) | (k, v) <- KM.toList km, isObjectValue v]
  fmap M.fromList $ traverse (\(k, v) -> (k,) <$> parseJSON v) pairs
  where
    isObjectValue (Object _) = True
    isObjectValue _          = False

-- ─────────────────────────────────────────────────────────────────────────────
-- JSON DECODING
-- ─────────────────────────────────────────────────────────────────────────────

data IrDocument = IrDocument
  { irSource       :: IrSource
  , irMetadata     :: IrMetadata
  , irRoles        :: M.Map String IrRole
  , irObjects      :: M.Map String IrObject
  , irBehaviors    :: IrBehaviors
  , irDeclarations :: M.Map String [IrDeclaration]
  , irNormClauses  :: [IrNormClause]
  , irTemplates    :: M.Map String IrTemplate
  , irInstitution  :: IrInstitution
  } deriving (Show)

data IrSource = IrSource
  { irDate :: String
  } deriving (Show)

data IrMetadata = IrMetadata
  { irContractType :: String
  } deriving (Show)

data IrRole = IrRole
  { irRoleSubtype  :: String   -- "physical" | "legal"
  , irRoleCapacity :: String   -- "exercise" | "enjoy"
  } deriving (Show)

data IrObject = IrObject
  { irObjType    :: String   -- "Thing" | "Service"
  , irObjSubtype :: String   -- "non-movable" | "movable" | "expendable" | "positive" | "negative"
  , irHasMoneda  :: Bool     -- True if attributes.moneda is present
  } deriving (Show)

data IrBehaviors = IrBehaviors
  { irActs          :: M.Map String IrAct
  , irFacts         :: M.Map String IrFact
  , irFactForbidMap :: M.Map String IrFact   -- fact_predicates_for_prohibitions
  } deriving (Show)

data IrAct = IrAct
  { irActSignature :: [String]   -- [actor, object, target]
  } deriving (Show)

data IrFact = IrFact
  { irFactSignature :: [String]  -- [a, b]
  } deriving (Show)

data IrDeclaration = IrDeclaration
  { irDeclId           :: String
  , irDeclGeneratesFact :: Maybe String
  } deriving (Show)

data IrNormClause = IrNormClause
  { irClauseId         :: String
  , irClauseForm       :: String    -- "implies" | "constraint" | "definition" | "standalone_forbid" | "declaration"
  , irClauseAntFact    :: Maybe String
  , irClauseAntAct     :: Maybe String
  , irClauseDeontic    :: Maybe String  -- "oblig" | "forbid" | "claim" | "privilege"
  , irClauseAct        :: Maybe String  -- predicate name for act
  , irClauseFactPred   :: Maybe String  -- predicate name for fact predicate (forbid only)
  , irClauseEffect     :: Maybe String  -- effect-only consequent
  } deriving (Show)

data IrTemplate = IrTemplate
  { irTmplDescription :: String
  , irTmplParams      :: M.Map String IrParam
  } deriving (Show)

data IrParam = IrParam
  { irParamType    :: String   -- "predicate" | "role"
  , irParamBindsTo :: String
  } deriving (Show)

data IrInstitution = IrInstitution
  { irInstName :: String
  } deriving (Show)

-- ─── FromJSON instances ───────────────────────────────────────────────────────

instance FromJSON IrDocument where
  parseJSON = withObject "IrDocument" $ \o -> do
    src     <- o .: "source"
    meta    <- o .: "metadata"
    rolesV  <- o .: "roles"
    roles   <- parseMapFiltered rolesV
    objsV   <- o .:? "objects" .!= Object KM.empty
    objs    <- parseMapFiltered objsV
    behs    <- o .: "behaviors"
    declsV  <- o .:? "declarations" .!= Object KM.empty
    decls   <- parseMapFiltered declsV
    pc      <- o .: "principal_contract"
    clauses <- pc .: "normative_clauses"
    tmplsV  <- pc .:? "templates" .!= Object KM.empty
    tmpls   <- parseMapFiltered tmplsV
    inst    <- o .: "institution"
    pure (IrDocument src meta roles objs behs decls clauses tmpls inst)

instance FromJSON IrSource where
  parseJSON = withObject "IrSource" $ \o -> IrSource
    <$> o .: "date"

instance FromJSON IrMetadata where
  parseJSON = withObject "IrMetadata" $ \o -> IrMetadata
    <$> o .: "contract_type"

instance FromJSON IrRole where
  parseJSON = withObject "IrRole" $ \o -> do
    subtype  <- o .:? "subtype" .!= "physical"
    mAttrs   <- o .:? "attributes"
    capacity <- case mAttrs of
      Just (Object av) -> fromMaybe "exercise" <$> (av .:? "capacity")
      _                -> pure "exercise"
    pure (IrRole subtype capacity)

instance FromJSON IrObject where
  parseJSON = withObject "IrObject" $ \o -> do
    t      <- o .: "type"
    st     <- o .:? "subtype" .!= "movable"
    mAttrs <- o .:? "attributes"
    let hasM = case mAttrs of
          Just (Object av) -> KM.member (fromString "moneda") av
          _                -> False
    pure (IrObject t st hasM)

instance FromJSON IrBehaviors where
  parseJSON = withObject "IrBehaviors" $ \o -> do
    actsV    <- o .:? "acts" .!= Object KM.empty
    acts     <- parseMapFiltered actsV
    factsV   <- o .:? "facts" .!= Object KM.empty
    facts    <- parseMapFiltered factsV
    forbidsV <- o .:? "fact_predicates_for_prohibitions" .!= Object KM.empty
    forbids  <- parseMapFiltered forbidsV
    pure (IrBehaviors acts facts forbids)

instance FromJSON IrAct where
  parseJSON = withObject "IrAct" $ \o -> IrAct
    <$> o .: "signature"

instance FromJSON IrFact where
  parseJSON = withObject "IrFact" $ \o -> IrFact
    <$> o .: "signature"

instance FromJSON IrDeclaration where
  parseJSON = withObject "IrDeclaration" $ \o -> IrDeclaration
    <$> o .: "id"
    <*> o .:? "generates_fact"

instance FromJSON IrNormClause where
  parseJSON = withObject "IrNormClause" $ \o -> do
    cid     <- o .: "id"
    form    <- o .: "form"
    ant     <- o .:? "antecedent"
    consq   <- o .:? "consequent"
    antFact <- case ant of
      Just (Object av) -> av .:? "fact"
      _                -> pure Nothing
    antAct  <- case ant of
      Just (Object av) -> av .:? "act"
      _                -> pure Nothing
    deontic <- case consq of
      Just (Object cv) -> cv .:? "deontic"
      _                -> pure Nothing
    actRef  <- case consq of
      Just (Object cv) -> cv .:? "act"
      _                -> pure Nothing
    factRef <- case consq of
      Just (Object cv) -> cv .:? "fact_predicate"
      _                -> pure Nothing
    effect  <- case consq of
      Just (Object cv) -> cv .:? "effect"
      _                -> pure Nothing
    pure (IrNormClause cid form antFact antAct deontic actRef factRef effect)

instance FromJSON IrTemplate where
  parseJSON = withObject "IrTemplate" $ \o -> IrTemplate
    <$> (o .:? "description" .!= "")
    <*> (o .:? "parameters" .!= M.empty)

instance FromJSON IrParam where
  parseJSON = withObject "IrParam" $ \o -> IrParam
    <$> (o .:? "type" .!= "predicate")
    <*> o .: "binds_to"

instance FromJSON IrInstitution where
  parseJSON = withObject "IrInstitution" $ \o -> IrInstitution
    <$> o .: "name"

-- ─────────────────────────────────────────────────────────────────────────────
-- IDENTIFIER NORMALIZATION
-- ─────────────────────────────────────────────────────────────────────────────

-- | Convert snake_case to UpperCamelCase for DSL identifiers.
-- pago_renta → PagoRenta, deposito_garantia → DepositoGarantia
toDslId :: String -> String
toDslId s = concatMap capitalize (splitOn '_' (filter (\c -> isAlphaNum c || c == '_') s))
  where
    capitalize []     = []
    capitalize (c:cs) = toUpper c : cs

splitOn :: Char -> String -> [String]
splitOn _ [] = [""]
splitOn delim (x:xs)
  | x == delim = "" : splitOn delim xs
  | otherwise  = case splitOn delim xs of
      []       -> [[x]]
      (h:rest) -> (x:h) : rest

-- | Lower-case first character (for display labels).
lcFirst :: String -> String
lcFirst []     = []
lcFirst (c:cs) = toLower c : cs

-- | Title-case: capitalize first letter of each word split by underscore.
titleCase :: String -> String
titleCase = unwords . map capitalize . words . map (\c -> if c == '_' then ' ' else c)
  where
    capitalize []     = []
    capitalize (c:cs) = toUpper c : cs

-- ─────────────────────────────────────────────────────────────────────────────
-- VERB EXTRACTION
-- ─────────────────────────────────────────────────────────────────────────────

-- | Extract a canonical DSL verb from a predicate name.
-- Uses a small known-verb table; falls back to the first token.
extractVerb :: String -> String
extractVerb predName =
  let tokens = splitOn '_' predName
  in case tokens of
    []    -> "act"
    (t:_) -> fromMaybe t (M.lookup t verbTable)

verbTable :: M.Map String String
verbTable = M.fromList
  [ ("pago",      "pay")
  , ("paga",      "pay")
  , ("pague",     "pay")
  , ("conceda",   "grant")
  , ("devuelva",  "return")
  , ("entrega",   "deliver")
  , ("devolucion","return")
  , ("garantice", "guarantee")
  , ("conserve",  "conserve")
  , ("haga",      "improve")
  , ("almacene",  "store")
  , ("subarriende","sublease")
  , ("retenga",   "retain")
  , ("use",       "use")
  ]

-- ─────────────────────────────────────────────────────────────────────────────
-- OBJECT KIND EMISSION
-- ─────────────────────────────────────────────────────────────────────────────

objectKindDsl :: IrObject -> String
objectKindDsl obj =
  case (irObjType obj, irObjSubtype obj) of
    ("Thing", "non-movable") -> "nonmovable"
    ("Thing", "movable")     -> "movable"
    ("Thing", "expendable")
      | irHasMoneda obj      -> "money"
      | otherwise            -> "expendable"
    ("Service", "positive")  -> "service, performance"
    ("Service", "negative")  -> "service, omission"
    ("Service", _)           -> "service, performance"
    _                        -> "movable"

-- ─────────────────────────────────────────────────────────────────────────────
-- ACTION RECONSTRUCTION
-- ─────────────────────────────────────────────────────────────────────────────

-- | Look up a predicate in behaviors.acts and reconstruct the three DSL roles:
-- (actorAlias, objectAlias, targetAlias)
lookupActSignature :: IrBehaviors -> String -> Maybe (String, String, String)
lookupActSignature behaviors predName =
  case M.lookup predName (irActs behaviors) of
    Just act ->
      case irActSignature act of
        [actor, obj, target] -> Just (toDslId actor, toDslId obj, toDslId target)
        _                    -> Nothing
    Nothing -> Nothing

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPILER STATE
-- ─────────────────────────────────────────────────────────────────────────────

data CompilerState = CompilerState
  { csWarnings :: [String]
  , csLines    :: [String]
  }

emitLine :: String -> CompilerState -> CompilerState
emitLine l cs = cs { csLines = csLines cs ++ [l] }

emitBlank :: CompilerState -> CompilerState
emitBlank = emitLine ""

warn :: String -> CompilerState -> CompilerState
warn w cs = cs { csWarnings = csWarnings cs ++ [w] }

emitLines :: [String] -> CompilerState -> CompilerState
emitLines ls cs = foldl (flip emitLine) cs ls

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN EMITTER
-- ─────────────────────────────────────────────────────────────────────────────

-- | Convert an IrDocument to a DSL text string (no embedded comments).
-- Any lossy-conversion diagnostics are silently dropped; use
-- `irToDSLWithWarnings` if you want them.
irToDSL :: IrDocument -> String
irToDSL doc = unlines (runEmitter doc)

-- | Like `irToDSL` but also returns a list of diagnostic warning strings.
irToDSLWithWarnings :: IrDocument -> (String, [String])
irToDSLWithWarnings doc =
  let st = runEmitterState doc
  in (unlines (csLines st), csWarnings st)

-- Internal: run the emitter, return the final CompilerState.
runEmitterState :: IrDocument -> CompilerState
runEmitterState doc =
  let
    instName  = irInstName (irInstitution doc)
    enacted   = irDate (irSource doc)
    behaviors = irBehaviors doc

    actVerbs :: [(String, String)]
    actVerbs =
      sort . nub $
        [ (v, v)
        | predName <- M.keys (irActs behaviors)
        , let v = extractVerb predName
        , v /= "act"
        ]

    generatedFacts :: [String]
    generatedFacts =
      nub . sort . catMaybes $
        [ irDeclGeneratesFact d
        | declList <- M.elems (irDeclarations doc)
        , d <- declList
        ]

    implies     = filter (\c -> irClauseForm c `elem` ["implies", "standalone_forbid"]) (irNormClauses doc)
    obligs      = filter (\c -> irClauseDeontic c == Just "oblig") implies
    forbidActs  = filter (\c -> irClauseDeontic c == Just "forbid"
                              && irClauseFactPred c == Nothing
                              && irClauseAct c /= Nothing) implies
    forbidFacts = filter (\c -> irClauseDeontic c == Just "forbid"
                              && irClauseFactPred c /= Nothing) implies
    claims      = filter (\c -> irClauseDeontic c == Just "claim") implies
    privileges  = filter (\c -> irClauseDeontic c == Just "privilege") implies
    skippable   = filter (\c -> irClauseForm c `elem` ["constraint","definition"]
                              || (irClauseEffect c /= Nothing && irClauseDeontic c == Nothing)) (irNormClauses doc)

    st0  = CompilerState [] []
    st1  = emitHeader instName enacted st0
    st2  = emitVocabulary actVerbs st1
    st3  = emitParties (irRoles doc) st2
    st4  = emitObjects (irObjects doc) st3
    st5  = emitArticleDeclarations generatedFacts behaviors obligs claims privileges st4
    st6  = emitArticleProhibitions behaviors forbidActs st5
    st7  = recordForbidFacts forbidFacts st6
    st8  = recordSkippable skippable st7
    st9  = emitTemplates (irTemplates doc) behaviors st8
  in st9

-- | Thin wrapper that just returns the lines (warnings discarded).
runEmitter :: IrDocument -> [String]
runEmitter = csLines . runEmitterState

-- ─────────────────────────────────────────────────────────────────────────────
-- EMIT PHASES
-- ─────────────────────────────────────────────────────────────────────────────

emitHeader :: String -> String -> CompilerState -> CompilerState
emitHeader name enacted =
  emitLines
    [ "law " ++ name
    , "authority private"
    , "enacted " ++ enacted
    ]

emitVocabulary :: [(String, String)] -> CompilerState -> CompilerState
emitVocabulary [] cs = cs
emitVocabulary verbs cs =
  emitLines
    ( "" : "vocabulary"
    : map (\(s, c) -> "    verb " ++ s ++ ": " ++ c) verbs
    ) cs

emitParties :: M.Map String IrRole -> CompilerState -> CompilerState
emitParties rolesMap cs =
  let entries = sortBy (\(a,_) (b,_) -> compare a b) (M.toList rolesMap)
      partyLines = map renderParty entries
  in emitLines ("" : "parties" : partyLines) cs
  where
    renderParty (roleKey, role) =
      let alias       = toDslId roleKey
          displayName = titleCase roleKey
          subtype     = case irRoleSubtype role of
                          "legal" -> "legal person"
                          _       -> "natural person"
          capacity    = case irRoleCapacity role of
                          "enjoy" -> "enjoy capacity"
                          _       -> "exercise capacity"
      in "    " ++ alias ++ ": " ++ displayName ++ ", " ++ subtype ++ ", " ++ capacity

emitObjects :: M.Map String IrObject -> CompilerState -> CompilerState
emitObjects objMap cs =
  let entries = sortBy (\(a,_) (b,_) -> compare a b) (M.toList objMap)
      objLines = map renderObj entries
  in emitLines ("" : "objects" : objLines) cs
  where
    renderObj (objKey, obj) =
      let alias = toDslId objKey
          kind  = objectKindDsl obj
      in "    " ++ alias ++ ": " ++ kind

emitArticleDeclarations
  :: [String]
  -> IrBehaviors
  -> [IrNormClause]   -- obligs
  -> [IrNormClause]   -- claims
  -> [IrNormClause]   -- privileges
  -> CompilerState -> CompilerState
emitArticleDeclarations facts behaviors obligs claims privileges cs0 =
  let
    factLines =
      [ "    fact " ++ lcFirst (toDslId f) ++ " is present."
      | f <- facts
      ]
    obligLines = mapMaybe (renderOblig behaviors) obligs
    claimLines = mapMaybe (renderClaim behaviors) claims
    privLines  = mapMaybe (renderPriv behaviors) privileges
    body = factLines ++ map ("    "++) obligLines ++ map ("    "++) claimLines ++ map ("    "++) privLines
  in
    if null body
      then cs0
      else emitLines ("" : "article 1 NormativeClauses" : body) cs0

emitArticleProhibitions :: IrBehaviors -> [IrNormClause] -> CompilerState -> CompilerState
emitArticleProhibitions behaviors forbidActs cs0 =
  let prohibLines = mapMaybe (renderForbidAct behaviors) forbidActs
  in if null prohibLines
       then cs0
       else emitLines ("" : "article 2 Prohibitions" : map ("    "++) prohibLines) cs0

-- ─────────────────────────────────────────────────────────────────────────────
-- CLAUSE RENDERERS (action reconstruction)
-- ─────────────────────────────────────────────────────────────────────────────

renderOblig :: IrBehaviors -> IrNormClause -> Maybe String
renderOblig behaviors clause = do
  actPred <- irClauseAct clause
  (actor, obj, target) <- lookupActSignature behaviors actPred
  let verb = extractVerb actPred
      antecedent = renderAntecedent behaviors clause
      consequent = actor ++ " must " ++ verb ++ " " ++ obj ++ " to " ++ target ++ "."
  Just $ "rule " ++ toDslId (irClauseId clause) ++ "\n" ++
         "        If " ++ antecedent ++ "\n" ++
         "        then " ++ consequent

renderClaim :: IrBehaviors -> IrNormClause -> Maybe String
renderClaim behaviors clause = do
  actPred <- irClauseAct clause
  (actor, obj, target) <- lookupActSignature behaviors actPred
  let verb = extractVerb actPred
      antecedent = renderAntecedent behaviors clause
      consequent = target ++ " may demand " ++ verb ++ " of " ++ obj ++ " from " ++ actor ++ "."
  Just $ "rule " ++ toDslId (irClauseId clause) ++ "\n" ++
         "        If " ++ antecedent ++ "\n" ++
         "        then " ++ consequent

renderPriv :: IrBehaviors -> IrNormClause -> Maybe String
renderPriv behaviors clause = do
  actPred <- irClauseAct clause
  (actor, obj, target) <- lookupActSignature behaviors actPred
  let verb = extractVerb actPred
      antecedent = renderAntecedent behaviors clause
      consequent = actor ++ " may " ++ verb ++ " " ++ obj ++ " to " ++ target ++ "."
  Just $ "rule " ++ toDslId (irClauseId clause) ++ "\n" ++
         "        If " ++ antecedent ++ "\n" ++
         "        then " ++ consequent

renderForbidAct :: IrBehaviors -> IrNormClause -> Maybe String
renderForbidAct behaviors clause = do
  actPred <- irClauseAct clause
  (actor, obj, target) <- lookupActSignature behaviors actPred
  let verb = extractVerb actPred
  Just $ "prohibition " ++ actor ++ " must not " ++ verb ++ " " ++ obj ++ " to " ++ target ++ "."

-- | Render the antecedent of a normative clause.
-- Uses fact or act referenced in the antecedent.
renderAntecedent :: IrBehaviors -> IrNormClause -> String
renderAntecedent behaviors clause =
  case (irClauseAntFact clause, irClauseAntAct clause) of
    (Just factPred, _) ->
      toDslId factPred ++ " is present"
    (_, Just actPred)  ->
      case lookupActSignature behaviors actPred of
        Just (actor, obj, target) ->
          actor ++ " " ++ extractVerb actPred ++ " " ++ obj ++ " to " ++ target
        Nothing -> toDslId actPred ++ " holds"
    _ -> "true"

-- ─────────────────────────────────────────────────────────────────────────────
-- WARNING RECORDING
-- ─────────────────────────────────────────────────────────────────────────────

recordForbidFacts :: [IrNormClause] -> CompilerState -> CompilerState
recordForbidFacts clauses cs =
  foldl step cs clauses
  where
    step acc clause =
      case irClauseFactPred clause of
        Just fp ->
          warn
            ( "[NOTE] IR clause '"
              ++ irClauseId clause
              ++ "' forbids fact predicate '"
              ++ fp
              ++ "' — no DSL equivalent; manual review required."
            )
            acc
        Nothing -> acc

recordSkippable :: [IrNormClause] -> CompilerState -> CompilerState
recordSkippable clauses cs =
  foldl step cs clauses
  where
    step acc clause =
      warn ("[SKIP] " ++ irClauseId clause ++ ": form='" ++ irClauseForm clause ++ "' — not representable in DSL") acc

-- ─────────────────────────────────────────────────────────────────────────────
-- TEMPLATE EMISSION
-- ─────────────────────────────────────────────────────────────────────────────

emitTemplates :: M.Map String IrTemplate -> IrBehaviors -> CompilerState -> CompilerState
emitTemplates tmplMap behaviors cs =
  let entries = sortBy (\(a,_) (b,_) -> compare a b) (M.toList tmplMap)
  in foldl (flip (uncurry (emitTemplate behaviors))) cs entries

emitTemplate :: IrBehaviors -> String -> IrTemplate -> CompilerState -> CompilerState
emitTemplate _behaviors tmplKey tmpl cs =
  let
    name   = toDslId tmplKey
    params = sortBy (\(a,_) (b,_) -> compare a b) (M.toList (irTmplParams tmpl))
    -- Include all params (predicate and role) as template params
    allParams = [ toDslId k | (k, _p) <- params ]
    paramList  = intercalate ", " allParams
    -- Generate a minimal compilable article body.
    -- Use `obligation` clause which accepts: Actor must verb Object.
    -- With predicate params standing in as actor / object identifiers.
    clauseBody = case allParams of
      (p1 : p2 : _) ->
        "        obligation " ++ p1 ++ " must perform " ++ p2 ++ "."
      (p1 : _) ->
        "        fact " ++ p1 ++ " is present."
      [] ->
        "        fact PlaceholderFact is present."
    block =
      [ ""
      , "template " ++ name ++ "(" ++ paramList ++ "):"
      , "    article 1 " ++ name ++ "Structure"
      , clauseBody
      ]
  in emitLines block cs
