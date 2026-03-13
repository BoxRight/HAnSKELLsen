module Main where

import Compiler.AST (lawEnactedAst)
import Compiler.Compiler
import Compiler.IRToDSL (irToDSL, irToDSLWithWarnings, IrDocument)
import Runtime.QuantaleAnalysis
  ( QuantaleOptions(..)
  , generateQuantaleReportWith
  , reachabilityReport
  , cyclesReport
  , criticalReport
  , violationPathsReport
  )
import Compiler.Imports
import Compiler.Parser
import Compiler.Scenario
import Compiler.Templates
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy (ByteString, hPut)
import qualified Data.ByteString.Lazy as LBS
import Data.ByteString.Lazy.Char8 (unpack)
import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe)
import Data.Time.Calendar (Day, fromGregorianValid)
import Pretty.PrettyReport (generateAuditReport)
import Runtime.Audit
import Runtime.AuditJson
import Runtime.DerivationGraph
import System.Environment (getArgs)
import System.IO (stdout, hPutStrLn, stderr)
import System.Exit (die)
import Text.Megaparsec (errorBundlePretty)
import qualified Data.Map.Strict as M

defaultInputPath :: FilePath
defaultInputPath = "lawlib/instantiations/composed_lease_regime.dsl"

data OutputFormat = FormatText | FormatJson
  deriving (Eq, Show)

data GraphFormat = GraphJson | GraphDot | GraphMermaid
  deriving (Eq, Show)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("quantale" : rest) -> runQuantaleMode rest
    ("ir" : rest)       -> runIrMode rest
    _                   -> runAuditMode args

runQuantaleMode :: [String] -> IO ()
runQuantaleMode args = do
  qopts <- either die pure (parseQuantaleOptions args)
  let inputPath = qInputPath qopts
  input <- readFile inputPath
  case parseLawFile inputPath input of
    Left bundle -> die (errorBundlePretty bundle)
    Right surfaceLawModule -> do
      resolvedImports <- resolveImports surfaceLawModule
      case resolvedImports of
        Left diagnostics -> die (unlines (map show diagnostics))
        Right composedSurfaceLaw ->
          case expandTemplates composedSurfaceLaw of
            Left diagnostics -> die (unlines (map show diagnostics))
            Right lawModule ->
              case compileLawModule lawModule of
                Left diagnostics -> die (unlines (map show diagnostics))
                Right compiled ->
                  case compileScenarios lawModule of
                    Left diagnostics -> die (unlines (map show diagnostics))
                    Right scenarios ->
                      putStrLn (runQuantaleQuery compiled scenarios qopts)

parseQuantaleOptions :: [String] -> Either String QuantaleOptions
parseQuantaleOptions args =
  go defaultOpts args
  where
    defaultOpts =
      QuantaleOptions
        { qInputPath = defaultInputPath
        , qReachability = Nothing
        , qCycles = False
        , qCritical = False
        , qViolationPaths = False
        }
    go opts [] = Right opts
    go opts ("--reachability" : label : rest) =
      go opts { qReachability = Just label } rest
    go opts ("--reachability" : []) =
      Left "--reachability requires an act label"
    go opts ("--cycles" : rest) =
      go opts { qCycles = True } rest
    go opts ("--critical" : rest) =
      go opts { qCritical = True } rest
    go opts ("--violation-paths" : rest) =
      go opts { qViolationPaths = True } rest
    go opts (arg : rest)
      | "--" `isPrefixOf` arg =
          Left ("unknown quantale option `" ++ arg ++ "`")
      | qInputPath opts == defaultInputPath =
          go opts { qInputPath = arg } rest
      | otherwise =
          Left ("unexpected extra argument `" ++ arg ++ "`")

runQuantaleQuery :: CompiledLawModule -> [CompiledScenario] -> QuantaleOptions -> String
runQuantaleQuery compiled scenarios opts
  | Just label <- qReachability opts =
      reachabilityReport compiled scenarios label
  | qCycles opts =
      cyclesReport compiled scenarios
  | qCritical opts =
      criticalReport compiled scenarios
  | qViolationPaths opts =
      violationPathsReport compiled scenarios
  | otherwise =
      generateQuantaleReportWith compiled scenarios opts

-- ─────────────────────────────────────────────────────────────────────────────
-- IR MODE
-- ─────────────────────────────────────────────────────────────────────────────

runIrMode :: [String] -> IO ()
runIrMode args = do
  (inputPath, mOutputPath) <- either die pure (parseIrOptions args)
  raw <- LBS.readFile inputPath
  case eitherDecode raw :: Either String [IrDocument] of
    Left err -> die ("IR JSON decode error: " ++ err)
    Right []  -> die "IR JSON: empty array"
    Right (doc:_) -> do
      let (dslText, warnings) = irToDSLWithWarnings doc
      mapM_ (\w -> hPutStrLn stderr ("-- " ++ w)) warnings
      case mOutputPath of
        Nothing   -> putStr dslText
        Just path -> writeFile path dslText

parseIrOptions :: [String] -> Either String (FilePath, Maybe FilePath)
parseIrOptions args =
  go Nothing Nothing args
  where
    go (Just inp) mOut [] = Right (inp, mOut)
    go Nothing _ [] = Left "ir mode requires an input JSON file"
    go inp _ ("-o" : path : rest) = go inp (Just path) rest
    go inp _ ("-o" : []) = Left "-o requires a file path"
    go Nothing mOut (arg : rest)
      | "--" `isPrefixOf` arg = Left ("unknown ir option `" ++ arg ++ "`")
      | otherwise = go (Just arg) mOut rest
    go (Just _) _ (arg : _) = Left ("unexpected extra argument `" ++ arg ++ "`")

-- ─────────────────────────────────────────────────────────────────────────────
-- AUDIT MODE
-- ─────────────────────────────────────────────────────────────────────────────

runAuditMode :: [String] -> IO ()
runAuditMode args = do
  options <- either die pure (parseCliOptions args)
  let inputPath = fromMaybe defaultInputPath (cliInputPath options)
  input <- readFile inputPath
  case parseLawFile inputPath input of
    Left bundle ->
      die (errorBundlePretty bundle)
    Right surfaceLawModule ->
      do
        resolvedImports <- resolveImports surfaceLawModule
        case resolvedImports of
          Left diagnostics ->
            die (unlines (map show diagnostics))
          Right composedSurfaceLaw ->
            case expandTemplates composedSurfaceLaw of
              Left diagnostics ->
                die (unlines (map show diagnostics))
              Right lawModule -> do
                mapM_ (hPutStrLn stderr . ("lint: " ++) . show)
                  (lintFactEventConfusion lawModule)
                case compileLawModule lawModule of
                  Left diagnostics ->
                    die (unlines (map show diagnostics))
                  Right compiled -> do
                    case compileScenarios lawModule of
                      Left diagnostics ->
                        die (unlines (map show diagnostics))
                      Right scenarios ->
                        runAuditOrReplay compiled scenarios options

runAuditOrReplay :: CompiledLawModule -> [CompiledScenario] -> CliOptions -> IO ()
runAuditOrReplay compiled scenarios options
  | cliReplay options =
      case cliScenarioName options of
        Nothing -> die "--replay requires --scenario"
        Just scenarioName ->
          case runAuditReplay compiled scenarios scenarioName of
            Left err -> die err
            Right replay ->
              outputReplay compiled options replay
  | otherwise = do
      auditDay <- either die pure (resolveAuditDay compiled scenarios options)
      case runAudit compiled scenarios (cliScenarioName options) auditDay of
        Left err -> die err
        Right auditResult -> outputAudit compiled options auditResult

outputAudit :: CompiledLawModule -> CliOptions -> AuditResult -> IO ()
outputAudit compiled options result = do
  case cliGraphFormat options of
    Just fmt -> putStrLn (outputGraph fmt compiled result)
    Nothing ->
      case cliOutputFormat options of
        FormatJson -> putLbs (auditResultToJson compiled result)
        FormatText -> putStrLn (generateAuditReport compiled result)

outputReplay :: CompiledLawModule -> CliOptions -> [(Day, AuditResult)] -> IO ()
outputReplay compiled options replay = do
  case cliOutputFormat options of
    FormatJson -> putLbs (auditReplayToJson compiled replay)
    FormatText ->
      mapM_
        (\(day, result) -> do
          putStrLn ("=== " ++ show day ++ " ===")
          putStrLn (generateAuditReport compiled result)
          putStrLn "")
        replay

outputGraph :: GraphFormat -> CompiledLawModule -> AuditResult -> String
outputGraph fmt compiled result =
  let graph = buildDerivationGraph compiled result
  in case fmt of
    GraphJson -> unpack (exportDerivationGraphJson graph)
    GraphDot -> exportDerivationGraphDot graph
    GraphMermaid -> exportDerivationGraphMermaid graph

putLbs :: ByteString -> IO ()
putLbs = hPut stdout

data CliOptions = CliOptions
  { cliInputPath :: Maybe FilePath
  , cliScenarioName :: Maybe String
  , cliAuditAt :: Maybe Day
  , cliReplay :: Bool
  , cliOutputFormat :: OutputFormat
  , cliGraphFormat :: Maybe GraphFormat
  }

emptyCliOptions :: CliOptions
emptyCliOptions =
  CliOptions
    { cliInputPath = Nothing
    , cliScenarioName = Nothing
    , cliAuditAt = Nothing
    , cliReplay = False
    , cliOutputFormat = FormatText
    , cliGraphFormat = Nothing
    }

parseCliOptions :: [String] -> Either String CliOptions
parseCliOptions =
  go emptyCliOptions
  where
    go options [] = Right options
    go options ("--scenario" : name : rest) =
      go options { cliScenarioName = Just name } rest
    go options ("--audit-at" : rawDate : rest) = do
      parsedDay <- maybe (Left ("invalid audit date `" ++ rawDate ++ "`")) Right (parseIsoDay rawDate)
      go options { cliAuditAt = Just parsedDay } rest
    go options ("--replay" : rest) =
      go options { cliReplay = True } rest
    go options ("--format" : "json" : rest) =
      go options { cliOutputFormat = FormatJson } rest
    go options ("--format" : other : rest) =
      Left ("unknown format `" ++ other ++ "` (use json)")
    go options ("--format" : []) =
      Left "--format requires a value (use json)"
    go options ("--graph" : "json" : rest) =
      go options { cliGraphFormat = Just GraphJson } rest
    go options ("--graph" : "dot" : rest) =
      go options { cliGraphFormat = Just GraphDot } rest
    go options ("--graph" : "mermaid" : rest) =
      go options { cliGraphFormat = Just GraphMermaid } rest
    go options ("--graph" : other : rest) =
      Left ("unknown graph format `" ++ other ++ "` (use json, dot, or mermaid)")
    go options ("--graph" : []) =
      Left "--graph requires a value (use json, dot, or mermaid)"
    go options (arg : rest)
      | "--" `isPrefixOf` arg =
          Left ("unknown option `" ++ arg ++ "`")
      | cliInputPath options == Nothing =
          go options { cliInputPath = Just arg } rest
      | otherwise =
          Left ("unexpected extra argument `" ++ arg ++ "`")

resolveAuditDay :: CompiledLawModule -> [CompiledScenario] -> CliOptions -> Either String Day
resolveAuditDay compiled scenarios options =
  case cliAuditAt options of
    Just day -> Right day
    Nothing ->
      case cliScenarioName options of
        Just name ->
          case lookupScenario scenarios name of
            Just scenario ->
              case M.lookupMax (compiledScenarioTimeline scenario) of
                Just (latestDay, _) -> Right latestDay
                Nothing -> Right (lawEnactedAst (compiledMetadata compiled))
            Nothing -> Left ("unknown scenario `" ++ name ++ "`")
        Nothing ->
          Right (lawEnactedAst (compiledMetadata compiled))

parseIsoDay :: String -> Maybe Day
parseIsoDay raw =
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
        chunk : rest -> (x : chunk) : rest

readMaybe :: Read a => String -> Maybe a
readMaybe raw =
  case reads raw of
    [(value, "")] -> Just value
    _ -> Nothing
