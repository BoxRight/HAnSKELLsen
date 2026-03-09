module Compiler.Parser
  ( Parser
  , parseLawFile
  , parseLawModule
  ) where

import Compiler.AST
import Capability (parseCapability)
import Control.Monad (void)
import Data.Char (isAlphaNum, isSpace, toLower)
import Data.List (dropWhileEnd, isInfixOf)
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
  | TopScenario ScenarioAst

data TemplateTopBlock
  = TemplateBlock TopBlock
  | TemplateInstantiateBlock TemplateInstantiateAst

data ProcedureEntry
  = ProcedureOr
  | ProcedureStep ActionPhraseAst

parseLawFile :: FilePath -> String -> Either (ParseErrorBundle String Void) SurfaceLawModuleAst
parseLawFile =
  runParser parseLawModule

parseLawModule :: Parser SurfaceLawModuleAst
parseLawModule = do
  skipBlankLines
  meta <- parseLawMeta
  filePath <- sourceName <$> getSourcePos
  forms <- many (try (skipBlankLines *> parseTopForm))
  skipBlankLines
  eof
  pure $
    SurfaceLawModuleAst
      { surfaceLawMeta = meta
      , surfaceLawPath = filePath
      , surfaceTopForms = map (Sourced meta filePath) forms
      }

parseTopForm :: Parser TopFormAst
parseTopForm =
  choice
    [ try parseImportTopForm
    , try parseTemplateDecl
    , try parseInstantiateTopForm
    , topBlockToTopForm <$> parseTopBlock
    ]

parseImportTopForm :: Parser TopFormAst
parseImportTopForm = do
  _ <- chunk "import"
  hspace1
  importPath <- char '"' *> manyTill anySingle (char '"')
  endOfLineOrEof
  pure (TopFormImport (ImportDeclAst importPath))

parseTemplateDecl :: Parser TopFormAst
parseTemplateDecl = do
  _ <- chunk "template"
  hspace1
  templateName <- identifier
  params <- parseTemplateParams
  hspace
  _ <- char ':'
  endOfLineOrEof
  bodyText <- parseIndentedBlockText 4
  bodyForms <-
    case runParser parseTemplateBodyForms ("template " ++ templateName) bodyText of
      Left bundle -> fail (errorBundlePretty bundle)
      Right forms -> pure forms
  pure $
    TopFormTemplate $
      TemplateDeclAst
        { templateNameAst = templateName
        , templateParamsAst = params
        , templateBodyAst = bodyForms
        }

parseInstantiateTopForm :: Parser TopFormAst
parseInstantiateTopForm =
  TopFormInstantiate <$> parseTemplateInstantiate

parseTemplateBodyForms :: Parser [TemplateBodyFormAst]
parseTemplateBodyForms = do
  skipBlankLines
  blocks <- many (try (skipBlankLines *> parseTemplateBodyBlock))
  skipBlankLines
  eof
  pure (map templateTopBlockToBodyForm blocks)

parseTemplateBodyBlock :: Parser TemplateTopBlock
parseTemplateBodyBlock =
  choice
    [ try (TemplateInstantiateBlock <$> parseTemplateInstantiate)
    , TemplateBlock <$> parseTopBlock
    ]

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
    , parseScenario
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
  rawBody <- trim <$> restOfLine
  let fields = splitCommaFields rawBody
      displayName =
        case fields of
          [] -> rawBody
          nameField : _ -> nameField
  subtype <- either fail pure (parsePartySubtype fields)
  capacity <- either fail pure (parsePartyCapacity fields)
  pure
    ( PartyDecl
        { partyAlias = alias
        , partyDisplayName = displayName
        , partySubtypeAst = subtype
        , partyCapacityAst = capacity
        , partyAddressAst = parsePartyAddress fields
        }
    )

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
  rawBody <- trim <$> restOfLine
  let fields = splitCommaFields rawBody
      primaryField =
        case fields of
          [] -> rawBody
          kindField : _ -> kindField
  kind <-
    case parseObjectKind primaryField of
      Just parsedKind -> pure parsedKind
      Nothing -> fail ("unknown object kind `" ++ primaryField ++ "`")
  serviceMode <- either fail pure (parseServiceMode kind fields)
  let relatedObject = parseObjectRelation fields
  startDay <- either fail pure (parseOptionalDatedField "start" fields)
  dueDay <- either fail pure (parseOptionalDatedField "due" fields)
  endDay <- either fail pure (parseOptionalDatedField "end" fields)
  pure
    ( ObjectDecl
        { objectAlias = alias
        , objectKind = kind
        , objectServiceMode = serviceMode
        , objectRelatedObject = relatedObject
        , objectStartAst = startDay
        , objectDueAst = dueDay
        , objectEndAst = endDay
        }
    )

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

parseScenario :: Parser TopBlock
parseScenario = do
  _ <- chunk "scenario"
  hspace1
  name <- manyTill anySingle (char ':')
  endOfLineOrEof
  entries <- some (try parseScenarioEntry)
  pure $
    TopScenario $
      ScenarioAst
        { scenarioName = trim name
        , scenarioEntries = entries
        }

parseTemplateInstantiate :: Parser TemplateInstantiateAst
parseTemplateInstantiate = do
  _ <- chunk "instantiate"
  hspace1
  templateName <- identifier
  bindings <- parseTemplateBindings
  endOfLineOrEof
  pure $
    TemplateInstantiateAst
      { instantiateTemplateName = templateName
      , instantiateBindings = bindings
      }

parseScenarioEntry :: Parser ScenarioEntryAst
parseScenarioEntry = do
  indent 4
  _ <- chunk "at"
  hspace1
  rawDate <- trim <$> restOfLine
  day <-
    case parseDay rawDate of
      Just parsedDay -> pure parsedDay
      Nothing -> fail ("invalid scenario date `" ++ rawDate ++ "`")
  assertions <- some (try parseScenarioAssertion)
  pure $
    ScenarioEntryAst
      { scenarioDate = day
      , scenarioAssertions = assertions
      }

parseScenarioAssertion :: Parser ScenarioAssertionAst
parseScenarioAssertion = do
  indent 8
  choice
    [ try parseScenarioNaturalEvent
    , try parseScenarioCounterAct
    , try parseScenarioAct
    , try parseScenarioCondition
    , try parseScenarioEvent
    ]

parseScenarioAct :: Parser ScenarioAssertionAst
parseScenarioAct = do
  _ <- chunk "act"
  hspace1
  body <- trim <$> restOfLine
  ScenarioAct <$> either fail pure (parseActionSentence body)

parseScenarioCounterAct :: Parser ScenarioAssertionAst
parseScenarioCounterAct = do
  _ <- chunk "counteract"
  hspace1
  body <- trim <$> restOfLine
  ScenarioCounterAct <$> either fail pure (parseCounterActionSentence body)

parseScenarioCondition :: Parser ScenarioAssertionAst
parseScenarioCondition = do
  _ <- chunk "assert"
  hspace1
  body <- trim <$> restOfLine
  ScenarioCondition <$> either fail pure (parseConditionSentence body)

parseScenarioEvent :: Parser ScenarioAssertionAst
parseScenarioEvent = do
  _ <- chunk "event"
  hspace1
  ScenarioEvent . HumanEventAst . trim <$> restOfLine

parseScenarioNaturalEvent :: Parser ScenarioAssertionAst
parseScenarioNaturalEvent = do
  _ <- chunk "natural event"
  hspace1
  ScenarioEvent . NaturalEventAst . trim <$> restOfLine

parseArticleClause :: Parser ClauseAst
parseArticleClause = do
  indent 4
  choice
    [ try parseProcedureClause
    , try parseRuleClause
    , try parseOverrideClause
    , try parseSuspendClause
    , try parseFactClause
    , try parseObligationClause
    , try parseClaimClause
    , try parseProhibitionClause
    , try parsePrivilegeClause
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

parsePrivilegeClause :: Parser ClauseAst
parsePrivilegeClause = do
  _ <- chunk "privilege"
  hspace1
  body <- trim <$> restOfLine
  modality <- either fail pure (parsePrivilegeSentence body)
  pure (ClauseModality modality)

parseOverrideClause :: Parser ClauseAst
parseOverrideClause = do
  _ <- chunk "override"
  hspace1
  targetLine <- trim <$> restOfLine
  (target, condLine) <-
    case splitOnOverrideBy targetLine of
      Nothing -> fail ("expected `override <modality> by <condition>` in `" ++ targetLine ++ "`")
      Just (t, c) -> pure (t, c)
  targetMod <- either fail pure (parseModalityForOverride target)
  condition <- either fail pure (parseConditionSentence condLine)
  pure (ClauseOverride (OverrideClauseAst targetMod condition))

parseSuspendClause :: Parser ClauseAst
parseSuspendClause = do
  _ <- chunk "suspend"
  hspace1
  targetLine <- trim <$> restOfLine
  (target, condLine) <-
    case splitOnOverrideBy targetLine of
      Nothing -> fail ("expected `suspend <modality> by <condition>` in `" ++ targetLine ++ "`")
      Just (t, c) -> pure (t, c)
  targetMod <- either fail pure (parseModalityForOverride target)
  condition <- either fail pure (parseConditionSentence condLine)
  pure (ClauseSuspend (SuspendClauseAst targetMod condition))

splitOnOverrideBy :: String -> Maybe (String, String)
splitOnOverrideBy s =
  case splitInfix " by " s of
    Nothing -> Nothing
    Just (before, after) -> Just (trim before, trim after)

parseModalityForOverride :: String -> Either String ModalityAst
parseModalityForOverride raw
  | tokenizedContains ["may", "demand"] raw = parseClaimSentence raw
  | tokenizedContains ["may"] raw = parsePrivilegeSentence raw
  | tokenizedContains ["must", "not"] raw = parseProhibitionSentence raw
  | tokenizedContains ["must"] raw = parseObligationSentence raw
  | otherwise = Left ("unsupported modality for override/suspend `" ++ raw ++ "`")

parseFactClause :: Parser ClauseAst
parseFactClause = do
  _ <- chunk "fact"
  hspace1
  body <- trim <$> restOfLine
  factAst <- either fail pure (parseInstitutionalFactSentence body)
  pure (ClauseStandingFact factAst)

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
  validityLines <- many (try (indent 8 *> parseValidityLine))
  condition <- either fail pure (parseConditionSentence conditionLine)
  consequence <- either fail pure (parseConsequentSentence consequenceLine)
  (validFrom, validTo) <- either fail pure (parseValidityLines validityLines)
  pure $
    ClauseRule $
      RuleAst
        { ruleNameAst = ruleName
        , ruleConditionAst = condition
        , ruleConsequentAst = consequence
        , ruleValidFromAst = validFrom
        , ruleValidToAst = validTo
        }
  where
    parseValidityLine :: Parser String
    parseValidityLine = do
      _ <- chunk "valid"
      hspace1
      trim <$> restOfLine
    parseValidityLines :: [String] -> Either String (Maybe Day, Maybe Day)
    parseValidityLines [] = Right (Nothing, Nothing)
    parseValidityLines (line : _) =
      case words (map toLower line) of
        "from" : rest ->
          case break (== "to") rest of
            (fromParts, []) ->
              case parseDay (unwords fromParts) of
                Just d -> Right (Just d, Nothing)
                Nothing -> Left ("invalid validity date in `" ++ line ++ "`")
            (fromParts, _ : toParts) ->
              case (parseDay (unwords fromParts), parseDay (unwords toParts)) of
                (Just d1, Just d2) -> Right (Just d1, Just d2)
                _ -> Left ("invalid validity dates in `" ++ line ++ "`")
        _ -> Left ("expected `valid from <date>` or `valid from <date> to <date>` in `" ++ line ++ "`")

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
  if tokenizedContains ["must"] raw
    then ObligationAst <$> parseActionSentence raw
    else Left ("expected obligation form with `must` in `" ++ raw ++ "`")

parseClaimSentence :: String -> Either String ModalityAst
parseClaimSentence raw =
  ClaimAst <$> parseDemandSentence raw

parseProhibitionSentence :: String -> Either String ModalityAst
parseProhibitionSentence raw =
  case parseActionSentence raw of
    Right action ->
      if tokenizedContains ["must", "not"] raw || tokenizedContains ["must", "refrain", "from"] raw
        then Right (ProhibitionAst action)
        else
          Left
            ("expected prohibition form with `must not` or `must refrain from` in `" ++ raw ++ "`")
    Left err -> Left err

parsePrivilegeSentence :: String -> Either String ModalityAst
parsePrivilegeSentence raw =
  if tokenizedContains ["may"] raw
    then PrivilegeAst <$> parseActionSentence raw
    else Left ("expected privilege form with `may` in `" ++ raw ++ "`")

parseConsequentSentence :: String -> Either String ModalityAst
parseConsequentSentence raw
  | tokenizedContains ["may", "demand"] raw = parseClaimSentence raw
  | tokenizedContains ["may"] raw = parsePrivilegeSentence raw
  | tokenizedContains ["must", "not"] raw = parseProhibitionSentence raw
  | tokenizedContains ["must"] raw = parseObligationSentence raw
  | otherwise = Left ("unsupported consequence `" ++ raw ++ "`")

parseConditionSentence :: String -> Either String ConditionAst
parseConditionSentence raw =
  case splitConditionConjunction raw of
    [single] -> parseSingleCondition single
    parts -> do
      conditions <- mapM parseSingleCondition parts
      Right (ConditionConjunctionAst conditions)

parseSingleCondition :: String -> Either String ConditionAst
parseSingleCondition raw =
  case parseInstitutionalFactSentence raw of
    Right factAst -> Right (InstitutionalConditionAst factAst)
    Left _ ->
      case parseEventCondition raw of
        Right eventAst -> Right (EventConditionAst eventAst)
        Left _ ->
          ActionConditionAst <$> parseActionSentence raw

parseEventCondition :: String -> Either String LegalEventAst
parseEventCondition raw =
  case words (stripSentence raw) of
    "event" : rest ->
      Right (HumanEventAst (unwords rest))
    "natural" : "event" : rest ->
      Right (NaturalEventAst (unwords rest))
    _ -> Left ("not an event condition: " ++ raw)

splitConditionConjunction :: String -> [String]
splitConditionConjunction raw =
  splitOnConjunction " and " (stripSentence raw)

splitOnConjunction :: String -> String -> [String]
splitOnConjunction _ [] = []
splitOnConjunction sep s
  | sep `isInfixOf` s =
      let (before, rest) = breakOnFirst sep s
          after = drop (length sep) rest
      in trim before : splitOnConjunction sep after
  | otherwise = [trim s | not (null (trim s))]

breakOnFirst :: String -> String -> (String, String)
breakOnFirst sep s =
  case splitInfix sep s of
    Nothing -> (s, [])
    Just (before, after) -> (before, after)

splitInfix :: Eq a => [a] -> [a] -> Maybe ([a], [a])
splitInfix [] _ = Just ([], [])
splitInfix _ [] = Nothing
splitInfix needle haystack =
  findAt 0 haystack
  where
    findAt i s
      | length s < length needle = Nothing
      | take (length needle) s == needle =
          Just (take i haystack, drop (i + length needle) haystack)
      | otherwise = findAt (i + 1) (tail s)

parseActionSentence :: String -> Either String ActionPhraseAst
parseActionSentence raw =
  case words (stripSentence raw) of
    actorName : "must" : "refrain" : "from" : verbName : objectName : rest ->
      buildAction NegativeActionAst actorName verbName objectName rest
    actorName : "may" : "refrain" : "from" : verbName : objectName : rest ->
      buildAction NegativeActionAst actorName verbName objectName rest
    actorName : "fails" : "to" : verbName : objectName : rest ->
      buildAction NegativeActionAst actorName verbName objectName rest
    actorName : "does" : "not" : verbName : objectName : rest ->
      buildAction NegativeActionAst actorName verbName objectName rest
    actorName : "must" : "not" : verbName : objectName : rest ->
      buildAction NegativeActionAst actorName verbName objectName rest
    actorName : "must" : verbName : objectName : rest ->
      buildAction PositiveActionAst actorName verbName objectName rest
    actorName : "may" : verbName : objectName : rest ->
      buildAction PositiveActionAst actorName verbName objectName rest
    actorName : verbName : objectName : rest ->
      buildAction PositiveActionAst actorName verbName objectName rest
    _ ->
      Left
        ("unsupported action phrase `" ++ raw ++ "`")

parseCounterActionSentence :: String -> Either String ActionPhraseAst
parseCounterActionSentence raw =
  case parseActionSentence raw of
    Right action
      | actionPolarity action == NegativeActionAst -> Right action
    Right _ ->
      Left ("expected counter-act form in `" ++ raw ++ "`")
    Left err ->
      Left err

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

buildAction :: ActionPolarityAst -> String -> String -> String -> [String] -> Either String ActionPhraseAst
buildAction polarity actorName verbName objectName rest =
  case rest of
    [] ->
      Right $
        ActionPhraseAst
          { actionActorName = actorName
          , actionVerb = verbName
          , actionObjectName = objectName
          , actionTargetName = Nothing
          , actionPolarity = polarity
          }
    ["to", targetName] ->
      Right $
        ActionPhraseAst
          { actionActorName = actorName
          , actionVerb = verbName
          , actionObjectName = objectName
          , actionTargetName = Just targetName
          , actionPolarity = polarity
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

parseTemplateParams :: Parser [String]
parseTemplateParams =
  between (char '(') (char ')')
    (sepBy (trim <$> identifier) (hspace *> char ',' *> hspace))

parseTemplateBindings :: Parser [TemplateBindingAst]
parseTemplateBindings =
  between (char '(') (char ')')
    (sepBy parseTemplateBinding (hspace *> char ',' *> hspace))

parseTemplateBinding :: Parser TemplateBindingAst
parseTemplateBinding = do
  paramName <- identifier
  hspace
  _ <- char '='
  hspace
  valueText <- trim <$> takeWhileP Nothing (\c -> c /= ',' && c /= ')' && c /= '\n' && c /= '\r')
  pure $
    TemplateBindingAst
      { bindingParamName = paramName
      , bindingValueText = valueText
      }

parseIndentedBlockText :: Int -> Parser String
parseIndentedBlockText width =
  concat <$> some (try parseIndentedLine <|> parseEmptyLine)
  where
    parseIndentedLine = do
      indent width
      content <- takeWhileP Nothing (\c -> c /= '\n' && c /= '\r')
      newline <- optional eol
      pure (content ++ maybe "" (const "\n") newline)

    parseEmptyLine = do
      _ <- optional (many (char ' '))
      _ <- eol
      pure "\n"

topBlockToTopForm :: TopBlock -> TopFormAst
topBlockToTopForm topBlock =
  case topBlock of
    TopParties parties -> TopFormParties parties
    TopObjects objects -> TopFormObjects objects
    TopVocabulary vocabulary -> TopFormVocabulary vocabulary
    TopArticle article -> TopFormArticle article
    TopScenario scenario -> TopFormScenario scenario

templateTopBlockToBodyForm :: TemplateTopBlock -> TemplateBodyFormAst
templateTopBlockToBodyForm templateBlock =
  case templateBlock of
    TemplateBlock topBlock ->
      case topBlock of
        TopParties parties -> TemplateBodyParties parties
        TopObjects objects -> TemplateBodyObjects objects
        TopVocabulary vocabulary -> TemplateBodyVocabulary vocabulary
        TopArticle article -> TemplateBodyArticle article
        TopScenario scenario -> TemplateBodyScenario scenario
    TemplateInstantiateBlock instantiation ->
      TemplateBodyInstantiate instantiation

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

splitCommaFields :: String -> [String]
splitCommaFields raw =
  filter (not . null) (map trim (splitOn ',' raw))

parsePartySubtype :: [String] -> Either String PartySubtypeAst
parsePartySubtype fields =
  case [subtype | field <- drop 1 fields, subtype <- maybeToList (partySubtypeField field)] of
    [] -> Right NaturalPartyAst
    [subtype] -> Right subtype
    _ -> Left "party declaration has conflicting subtype descriptors"

parsePartyCapacity :: [String] -> Either String PartyCapacityAst
parsePartyCapacity fields =
  case [capacity | field <- drop 1 fields, capacity <- maybeToList (partyCapacityField field)] of
    [] -> Right ExerciseCapacityAst
    [capacity] -> Right capacity
    _ -> Left "party declaration has conflicting capacity descriptors"

parsePartyAddress :: [String] -> Maybe String
parsePartyAddress fields =
  case [trim (dropPrefix "address" field) | field <- drop 1 fields, isPrefixedBy "address" field] of
    addressText : _ -> normalizeOptional (Just addressText)
    [] -> Nothing

partySubtypeField :: String -> Maybe PartySubtypeAst
partySubtypeField raw =
  case normalizeWord raw of
    "naturalperson" -> Just NaturalPartyAst
    "physicalperson" -> Just NaturalPartyAst
    "legalperson" -> Just LegalPartyAst
    _ -> Nothing

partyCapacityField :: String -> Maybe PartyCapacityAst
partyCapacityField raw =
  case normalizeWord raw of
    "enjoycapacity" -> Just EnjoyCapacityAst
    "exercisecapacity" -> Just ExerciseCapacityAst
    _ -> Nothing

parseServiceMode :: ObjectKindAst -> [String] -> Either String (Maybe ServiceModeAst)
parseServiceMode kind fields =
  case kind of
    ServiceKind ->
      case [mode | field <- fields, mode <- maybeToList (serviceModeField field)] of
        [] -> Right (Just PerformanceServiceAst)
        [mode] -> Right (Just mode)
        _ -> Left "object declaration has conflicting service descriptors"
    _ -> Right Nothing

serviceModeField :: String -> Maybe ServiceModeAst
serviceModeField raw =
  case normalizeWord raw of
    "performance" -> Just PerformanceServiceAst
    "omission" -> Just OmissionServiceAst
    _ -> Nothing

parseObjectRelation :: [String] -> Maybe String
parseObjectRelation fields =
  case [trim (dropPrefix "of" field) | field <- drop 1 fields, isPrefixedBy "of" field] of
    related : _ -> normalizeOptional (Just related)
    [] -> Nothing

parseOptionalDatedField :: String -> [String] -> Either String (Maybe Day)
parseOptionalDatedField label fields =
  case [trim (dropPrefix label field) | field <- drop 1 fields, isPrefixedBy label field] of
    [] -> Right Nothing
    [rawDate] ->
      case parseDay rawDate of
        Just parsedDay -> Right (Just parsedDay)
        Nothing -> Left ("invalid " ++ label ++ " date `" ++ rawDate ++ "`")
    _ -> Left ("object declaration has conflicting `" ++ label ++ "` fields")

parseInstitutionalFactSentence :: String -> Either String StandingFactAst
parseInstitutionalFactSentence raw =
  case words (stripSentence raw) of
    [partyName, "owns", objectName] ->
      Right (OwnershipFactAst partyName objectName)
    [capabilityName, "authority", "is", "present"] ->
      CapabilityFactAst <$> parseCapability capabilityName
    ["authority", capabilityName, "is", "present"] ->
      CapabilityFactAst <$> parseCapability capabilityName
    ["asset", assetName, "is", "present"] ->
      Right (AssetFactAst assetName)
    ["liability", liabilityName, "is", "present"] ->
      Right (LiabilityFactAst liabilityName)
    ["collateral", collateralName, "is", "present"] ->
      Right (CollateralFactAst collateralName)
    ["certification", certificationName, "is", "present"] ->
      Right (CertificationFactAst certificationName)
    "approved" : "contractor" : rest ->
      case splitAtEndOfContractor rest of
        (contractorName, ["is", "present"]) -> Right (ApprovedContractorFactAst contractorName)
        _ -> Left ("unsupported institutional fact `" ++ raw ++ "`")
    _ ->
      Left ("unsupported institutional fact `" ++ raw ++ "`")

splitAtEndOfContractor :: [String] -> (String, [String])
splitAtEndOfContractor ws =
  case break (== "is") ws of
    (nameParts, rest) -> (unwords nameParts, rest)

isPrefixedBy :: String -> String -> Bool
isPrefixedBy prefix raw =
  case words raw of
    firstWord : _ -> normalizeWord firstWord == normalizeWord prefix
    [] -> False

dropPrefix :: String -> String -> String
dropPrefix prefix raw =
  trim (drop (length prefix) raw)

normalizeWord :: String -> String
normalizeWord =
  map toLower . filter (\c -> isAlphaNum c || c == '_')

maybeToList :: Maybe a -> [a]
maybeToList maybeValue =
  case maybeValue of
    Just value -> [value]
    Nothing -> []

tokenizedContains :: [String] -> String -> Bool
tokenizedContains needle haystack =
  needle `isInfixOfList` words (map toLower (stripSentence haystack))

isInfixOfList :: Eq a => [a] -> [a] -> Bool
isInfixOfList [] _ = True
isInfixOfList _ [] = False
isInfixOfList needle haystack@(_ : xs) =
  needle == take (length needle) haystack || isInfixOfList needle xs
