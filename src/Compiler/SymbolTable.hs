module Compiler.SymbolTable
  ( Diagnostic(..)
  , SymbolTable(..)
  , buildSymbolTable
  , canonicalVerbRegistry
  , isCanonicalVerbInRegistry
  , normalizeSymbolKey
  , normalizeVerbToken
  , resolveFactDecl
  , resolveObjectDecl
  , resolveObjectVocabulary
  , resolvePartyDecl
  , resolveVerbCanonical
  ) where

import Compiler.AST as AST
import Data.Char (isAlphaNum, toLower)
import Data.Function (on)
import Data.List (foldl', intercalate, sortBy)
import qualified Data.Map.Strict as M
import qualified Data.Set as S

data Diagnostic = Diagnostic
  { diagnosticContext :: String
  , diagnosticMessage :: String
  }
  deriving (Eq, Ord)

instance Show Diagnostic where
  show (Diagnostic context message) =
    context ++ ": " ++ message

data SymbolTable = SymbolTable
  { partySymbols :: M.Map String PartyDecl
  , objectSymbols :: M.Map String ObjectDecl
  , verbSymbols :: M.Map String String
  , objectVocabularySymbols :: M.Map String String
  , factSymbols :: M.Map String AST.FactDecl
  }
  deriving (Eq, Show)

normalizeSymbolKey :: String -> String
normalizeSymbolKey =
  map toLower . filter (\c -> isAlphaNum c || c == '_')

normalizeVerbToken :: String -> String
normalizeVerbToken raw =
  case reverse normalized of
    's':rest -> reverse rest
    _ -> normalized
  where
    normalized = normalizeSymbolKey raw

-- | Default set of canonical verbs. Extensible; vocabulary may map surface verbs
-- to these or to controlled extensions (e.g. collect, apply, maintain for
-- usufruct/anticresis). baseVerbForObject outputs (transfer, deliver, perform,
-- refrain from, refrain from interfering with) must align with registry.
canonicalVerbRegistry :: S.Set String
canonicalVerbRegistry =
  S.fromList
    [ "transfer"
    , "pay"
    , "deliver"
    , "perform"
    , "refrain"
    , "refrain from"
    , "refrain from interfering with"
    , "collect"
    , "apply"
    , "maintain"
    , "notify"
    , "cancel"
    , "damage"
    ]

-- | Normalized registry for lookup (handles spaces in multi-word verbs).
canonicalVerbRegistryNormalized :: S.Set String
canonicalVerbRegistryNormalized =
  S.fromList (map normalizeSymbolKey (S.toList canonicalVerbRegistry))

isCanonicalVerbInRegistry :: String -> Bool
isCanonicalVerbInRegistry verb =
  S.member (normalizeSymbolKey verb) canonicalVerbRegistryNormalized

buildSymbolTable :: LawModuleAst -> Either [Diagnostic] SymbolTable
buildSymbolTable lawModule =
  case sortDiagnostics diagnostics of
    [] ->
      Right SymbolTable
        { partySymbols = partyMap
        , objectSymbols = objectMap
        , verbSymbols = verbMap
        , objectVocabularySymbols = objectVocabMap
        , factSymbols = factMap
        }
    errs -> Left errs
  where
    partyEntries = [ (partyAlias party, party) | party <- lawParties lawModule ]
    objectEntries = [ (objectAlias obj, obj) | obj <- lawObjects lawModule ]
    verbEntries =
      [ (surface, canonical)
      | VerbVocabulary surface canonical <- lawVocabulary lawModule
      ]
    objectVocabEntries =
      [ (surface, canonical)
      | ObjectVocabulary surface canonical <- lawVocabulary lawModule
      ]
    factEntries =
      [ (factDeclName f, f)
      | f <- lawFacts lawModule
      ]

    (partyMap, partyDiags) = buildMap "parties" "party" partyEntries
    (objectMap, objectDiags) = buildMap "objects" "object" objectEntries
    (verbMap, verbDiags) = buildMap "vocabulary" "verb" verbEntries
    (objectVocabMap, objectVocabDiags) =
      buildMap "vocabulary" "object vocabulary entry" objectVocabEntries
    (factMap, factDiags) = buildMap "facts" "fact" factEntries

    diagnostics =
      partyDiags ++ objectDiags ++ verbDiags ++ objectVocabDiags ++ factDiags

buildMap
  :: String
  -> String
  -> [(String, a)]
  -> (M.Map String a, [Diagnostic])
buildMap contextName entryName entries =
  foldl' step (M.empty, []) entries
  where
    step (accMap, accDiags) (rawKey, value) =
      let key = normalizeSymbolKey rawKey
      in case M.lookup key accMap of
          Nothing -> (M.insert key value accMap, accDiags)
          Just _ ->
            ( accMap
            , Diagnostic contextName
                ("duplicate " ++ entryName ++ " `" ++ rawKey ++ "`")
                : accDiags
            )

resolvePartyDecl :: SymbolTable -> String -> Either Diagnostic PartyDecl
resolvePartyDecl table rawName =
  lookupSymbol "resolution" "party" rawName (partySymbols table)

resolveObjectDecl :: SymbolTable -> String -> Either Diagnostic ObjectDecl
resolveObjectDecl table rawName =
  lookupSymbol "resolution" "object" rawName (objectSymbols table)

resolveVerbCanonical :: SymbolTable -> String -> Either Diagnostic String
resolveVerbCanonical table rawVerb =
  lookupSymbol "resolution" "verb" normalized (verbSymbols table)
  where
    normalized = normalizeVerbToken rawVerb

resolveObjectVocabulary :: SymbolTable -> String -> Maybe String
resolveObjectVocabulary table rawName =
  M.lookup (normalizeSymbolKey rawName) (objectVocabularySymbols table)

resolveFactDecl :: SymbolTable -> String -> Either Diagnostic AST.FactDecl
resolveFactDecl table rawName =
  lookupSymbol "facts" "fact" rawName (factSymbols table)

lookupSymbol
  :: String
  -> String
  -> String
  -> M.Map String a
  -> Either Diagnostic a
lookupSymbol contextName symbolName rawKey table =
  case M.lookup normalized table of
    Just value -> Right value
    Nothing ->
      Left $
        Diagnostic contextName
          ("unknown " ++ symbolName ++ " `" ++ rawKey ++ "`")
  where
    normalized = normalizeSymbolKey rawKey

sortDiagnostics :: [Diagnostic] -> [Diagnostic]
sortDiagnostics =
  sortBy (compare `on` renderDiagnostic)
  where
    renderDiagnostic diag =
      intercalate ":" [diagnosticContext diag, diagnosticMessage diag]
