module Compiler.Parser
  ( Parser
  , parseLawFile
  , parseLawModule
  ) where

import Compiler.AST
import Capability (parseCapability)
import Control.Monad (void)
import Data.Char (isAlphaNum, isSpace, toLower)
import Data.List (dropWhileEnd)
import Data.Time.Calendar (Day, fromGregorianValid)
import Data.Void (Void)
import NormativeGenerators (CapabilityIndex)
import Text.Megaparsec
import Text.Megaparsec.Char

type Parser = Parsec Void String

data TopBlock
  = TopParties [PartyDecl]
  | TopObjects [ObjectDecl]
  | TopVocabulary [VocabularyDecl]
  | TopArticle ArticleAst

data ProcedureEntry
  = ProcedureOr
  | ProcedureStep ActionPhraseAst

parseLawFile :: FilePath -> String -> Either (ParseErrorBundle String Void) LawModuleAst
parseLawFile =
  runParser parseLawModule

parseLawModule :: Parser LawModuleAst
parseLawModule = do
  skipBlankLines
  meta <- parseLawMeta
  blocks <- many (skipBlankLines *> parseTopBlock)
  skipBlankLines
  eof
  pure $
    LawModuleAst
      { lawMeta = meta
      , lawParties = concat [parties | TopParties parties <- blocks]
      , lawObjects = concat [objects | TopObjects objects <- blocks]
      , lawVocabulary = concat [vocab | TopVocabulary vocab <- blocks]
      , lawArticles = [article | TopArticle article <- blocks]
      }

parseLawMeta :: Parser LawMetaAst
parseLawMeta = do
  name <- parseNamedLine "law"
  authority <- parseAuthorityLine
  enacted <- parseEnactedLine
  pure $
    LawMetaAst
      { lawNameAst = name
      , lawAuthorityAst = authority
      , lawEnactedAst = enacted
      }

parseAuthorityLine :: Parser CapabilityIndex
parseAuthorityLine = do
  raw <- parseNamedLine "authority"
  case parseCapability raw of
    Left err -> fail err
    Right cap -> pure cap

parseEnactedLine :: Parser Day
parseEnactedLine = do
  raw <- parseNamedLine "enacted"
  case parseDay raw of
    Just day -> pure day
    Nothing -> fail ("invalid date `" ++ raw ++ "`")

parseTopBlock :: Parser TopBlock
parseTopBlock =
  choice
    [ parseVocabularySection
    , parsePartiesSection
    , parseObjectsSection
    , parseArticle
    ]

parseVocabularySection :: Parser TopBlock
parseVocabularySection = do
  _ <- chunk "vocabulary"
  endOfLineOrEof
  entries <- some (try parseVocabularyLine)
  pure (TopVocabulary entries)

parseVocabularyLine :: Parser VocabularyDecl
parseVocabularyLine = do
  indent 4
  kind <-
    choice
      [ chunk "verb" >> pure VerbVocabulary
      , chunk "object" >> pure ObjectVocabulary
      ]
  hspace1
  surface <- identifier
  _ <- char ':'
  hspace
  canonical <- trim <$> restOfLine
  pure (kind surface canonical)

parsePartiesSection :: Parser TopBlock
parsePartiesSection = do
  _ <- chunk "parties"
  endOfLineOrEof
  parties <- some (try parsePartyLine)
  pure (TopParties parties)

parsePartyLine :: Parser PartyDecl
parsePartyLine = do
  indent 4
  alias <- identifier
  _ <- char ':'
  hspace
  displayName <- trim <$> restOfLine
  pure (PartyDecl alias displayName)

parseObjectsSection :: Parser TopBlock
parseObjectsSection = do
  _ <- chunk "objects"
  endOfLineOrEof
  objects <- some (try parseObjectLine)
  pure (TopObjects objects)

parseObjectLine :: Parser ObjectDecl
parseObjectLine = do
  indent 4
  alias <- identifier
  _ <- char ':'
  hspace
  rawKind <- trim <$> restOfLine
  case parseObjectKind rawKind of
    Just kind -> pure (ObjectDecl alias kind)
    Nothing -> fail ("unknown object kind `" ++ rawKind ++ "`")

parseArticle :: Parser TopBlock
parseArticle = do
  _ <- chunk "article"
  hspace1
  number <- read <$> some digitChar
  heading <- optional (hspace1 *> (trim <$> restOfLine))
  case heading of
    Nothing -> endOfLineOrEof
    Just _ -> pure ()
  clauses <- some (try parseArticleClause)
  pure $
    TopArticle $
      ArticleAst
        { articleNumber = number
        , articleHeading = normalizeOptional heading
        , articleClauses = clauses
        }

parseArticleClause :: Parser ClauseAst
parseArticleClause = do
  indent 4
  choice
    [ try parseProcedureClause
    , try parseRuleClause
    , try parseObligationClause
    , try parseClaimClause
    , try parseProhibitionClause
    ]

parseObligationClause :: Parser ClauseAst
parseObligationClause = do
  _ <- chunk "obligation"
  hspace1
  body <- trim <$> restOfLine
  modality <- either fail pure (parseObligationSentence body)
  pure (ClauseModality modality)

parseClaimClause :: Parser ClauseAst
parseClaimClause = do
  _ <- chunk "claim"
  hspace1
  body <- trim <$> restOfLine
  modality <- either fail pure (parseClaimSentence body)
  pure (ClauseModality modality)

parseProhibitionClause :: Parser ClauseAst
parseProhibitionClause = do
  _ <- chunk "prohibition"
  hspace1
  body <- trim <$> restOfLine
  modality <- either fail pure (parseProhibitionSentence body)
  pure (ClauseModality modality)

parseProcedureClause :: Parser ClauseAst
parseProcedureClause = do
  _ <- chunk "procedure"
  hspace1
  name <- manyTill anySingle (char ':')
  endOfLineOrEof
  entries <- some (try parseProcedureEntry)
  branches <- either fail pure (splitProcedureEntries entries)
  pure $
    ClauseProcedure $
      ProcedureAst
        { procedureName = trim name
        , procedureBranches = branches
        }

parseProcedureEntry :: Parser ProcedureEntry
parseProcedureEntry = do
  indent 8
  raw <- trim <$> restOfLine
  if map toLower raw == "or"
    then pure ProcedureOr
    else ProcedureStep <$> either fail pure (parseActionSentence raw)

parseRuleClause :: Parser ClauseAst
parseRuleClause = do
  _ <- chunk "rule"
  hspace1
  ruleName <- trim <$> restOfLine
  indent 8
  _ <- string' "If"
  hspace1
  conditionLine <- trim <$> restOfLine
  indent 8
  _ <- string' "then"
  hspace1
  consequenceLine <- trim <$> restOfLine
  condition <- either fail pure (parseConditionSentence conditionLine)
  consequence <- either fail pure (parseConsequentSentence consequenceLine)
  pure $
    ClauseRule $
      RuleAst
        { ruleNameAst = ruleName
        , ruleConditionAst = condition
        , ruleConsequentAst = consequence
        }

parseNamedLine :: String -> Parser String
parseNamedLine name = do
  _ <- chunk name
  hspace1
  trim <$> restOfLine

parseObjectKind :: String -> Maybe ObjectKindAst
parseObjectKind raw =
  case normalizeWord raw of
    "movable" -> Just MovableKind
    "nonmovable" -> Just NonMovableKind
    "non_movable" -> Just NonMovableKind
    "expendable" -> Just ExpendableKind
    "money" -> Just MoneyKind
    "service" -> Just ServiceKind
    _ -> Nothing

parseObligationSentence :: String -> Either String ModalityAst
parseObligationSentence raw =
  ObligationAst <$> parseActionSentence raw

parseClaimSentence :: String -> Either String ModalityAst
parseClaimSentence raw =
  ClaimAst <$> parseDemandSentence raw

parseProhibitionSentence :: String -> Either String ModalityAst
parseProhibitionSentence raw =
  case parseActionSentence raw of
    Right action@(ActionPhraseAst actor verb obj target) ->
      if tokenizedContains ["must", "not"] raw
        then Right (ProhibitionAst action)
        else
          Left
            ("expected prohibition form with `must not` in `" ++ raw ++ "`")
    Left err -> Left err

parseConsequentSentence :: String -> Either String ModalityAst
parseConsequentSentence raw
  | tokenizedContains ["may", "demand"] raw = parseClaimSentence raw
  | tokenizedContains ["must", "not"] raw = parseProhibitionSentence raw
  | tokenizedContains ["must"] raw = parseObligationSentence raw
  | otherwise = Left ("unsupported consequence `" ++ raw ++ "`")

parseConditionSentence :: String -> Either String ConditionAst
parseConditionSentence raw =
  case words (stripSentence raw) of
    [partyName, "owns", objectName] ->
      Right (OwnershipConditionAst partyName objectName)
    _ ->
      Left
        ("unsupported condition `" ++ raw ++ "`")

parseActionSentence :: String -> Either String ActionPhraseAst
parseActionSentence raw =
  case words (stripSentence raw) of
    actorName : "must" : "not" : verbName : objectName : rest ->
      buildAction actorName verbName objectName rest
    actorName : "must" : verbName : objectName : rest ->
      buildAction actorName verbName objectName rest
    actorName : verbName : objectName : rest ->
      buildAction actorName verbName objectName rest
    _ ->
      Left
        ("unsupported action phrase `" ++ raw ++ "`")

parseDemandSentence :: String -> Either String ClaimPhraseAst
parseDemandSentence raw =
  case words (stripSentence raw) of
    holderName : "may" : "demand" : claimVerbName : "of" : objectName : "from" : againstName : [] ->
      Right $
        ClaimPhraseAst
          { claimHolderName = holderName
          , claimVerb = claimVerbName
          , claimObjectName = objectName
          , claimAgainstName = againstName
          }
    holderName : "may" : "demand" : objectName : "from" : againstName : [] ->
      Right $
        ClaimPhraseAst
          { claimHolderName = holderName
          , claimVerb = "demand"
          , claimObjectName = objectName
          , claimAgainstName = againstName
          }
    _ ->
      Left
        ("unsupported claim phrase `" ++ raw ++ "`")

buildAction :: String -> String -> String -> [String] -> Either String ActionPhraseAst
buildAction actorName verbName objectName rest =
  case rest of
    [] ->
      Right $
        ActionPhraseAst
          { actionActorName = actorName
          , actionVerb = verbName
          , actionObjectName = objectName
          , actionTargetName = Nothing
          }
    ["to", targetName] ->
      Right $
        ActionPhraseAst
          { actionActorName = actorName
          , actionVerb = verbName
          , actionObjectName = objectName
          , actionTargetName = Just targetName
          }
    _ ->
      Left
        ("unsupported action target in `" ++ unwords (actorName : verbName : objectName : rest) ++ "`")

splitProcedureEntries :: [ProcedureEntry] -> Either String [[ActionPhraseAst]]
splitProcedureEntries entries =
  finalizeBranches (foldl step ([[]], False) entries)
  where
    step (branches, justSawOr) entry =
      case entry of
        ProcedureStep action ->
          (appendToLast action branches, False)
        ProcedureOr ->
          (branches ++ [[]], True)

    finalizeBranches (branches, justSawOr)
      | justSawOr = Left "procedure cannot end with `or`"
      | any null branches = Left "procedure branches must contain at least one step"
      | otherwise = Right branches

appendToLast :: a -> [[a]] -> [[a]]
appendToLast _ [] = []
appendToLast x [ys] = [ys ++ [x]]
appendToLast x (ys : yss) = ys : appendToLast x yss

parseDay :: String -> Maybe Day
parseDay raw =
  case splitOn '-' raw of
    [yearStr, monthStr, dayStr] -> do
      year <- readMaybe yearStr
      month <- readMaybe monthStr
      day <- readMaybe dayStr
      fromGregorianValid year month day
    _ -> Nothing

splitOn :: Char -> String -> [String]
splitOn _ [] = [""]
splitOn delimiter (x : xs)
  | x == delimiter = "" : splitOn delimiter xs
  | otherwise =
      case splitOn delimiter xs of
        [] -> [[x]]
        (chunkText : rest) -> (x : chunkText) : rest

readMaybe :: Read a => String -> Maybe a
readMaybe raw =
  case reads raw of
    [(value, "")] -> Just value
    _ -> Nothing

indent :: Int -> Parser ()
indent width = void (count width (char ' '))

identifier :: Parser String
identifier = some (satisfy (\c -> isAlphaNum c || c == '_' || c == '-'))

restOfLine :: Parser String
restOfLine = do
  content <- takeWhileP Nothing (\c -> c /= '\n' && c /= '\r')
  endOfLineOrEof
  pure content

endOfLineOrEof :: Parser ()
endOfLineOrEof = void eol <|> eof

skipBlankLines :: Parser ()
skipBlankLines = void (many blankLine)
  where
    blankLine = try (hspace *> eol)

stripSentence :: String -> String
stripSentence = dropWhileEnd (`elem` ".;") . trim

trim :: String -> String
trim = dropWhile isSpace . dropWhileEnd isSpace

normalizeOptional :: Maybe String -> Maybe String
normalizeOptional maybeValue =
  case fmap trim maybeValue of
    Just "" -> Nothing
    other -> other

normalizeWord :: String -> String
normalizeWord =
  map toLower . filter (\c -> isAlphaNum c || c == '_')

tokenizedContains :: [String] -> String -> Bool
tokenizedContains needle haystack =
  needle `isInfixOfList` words (map toLower (stripSentence haystack))

isInfixOfList :: Eq a => [a] -> [a] -> Bool
isInfixOfList [] _ = True
isInfixOfList _ [] = False
isInfixOfList needle haystack@(_ : xs) =
  needle == take (length needle) haystack || isInfixOfList needle xs
