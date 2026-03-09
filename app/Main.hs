module Main where

import Compiler.AST (lawEnactedAst)
import Compiler.Compiler
import Compiler.Parser
import Compiler.Scenario
import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe)
import Data.Time.Calendar (Day, fromGregorianValid)
import Pretty.PrettyReport (generateAuditReport)
import Runtime.Audit
import System.Environment (getArgs)
import System.Exit (die)
import Text.Megaparsec (errorBundlePretty)
import qualified Data.Map.Strict as M

defaultInputPath :: FilePath
defaultInputPath = "lawlib/statutes/sales.dsl"

main :: IO ()
main = do
  args <- getArgs
  options <- either die pure (parseCliOptions args)
  let inputPath = fromMaybe defaultInputPath (cliInputPath options)
  input <- readFile inputPath
  case parseLawFile inputPath input of
    Left bundle ->
      die (errorBundlePretty bundle)
    Right lawModule ->
      case compileLawModule lawModule of
        Left diagnostics ->
          die (unlines (map show diagnostics))
        Right compiled -> do
          case compileScenarios lawModule of
            Left diagnostics ->
              die (unlines (map show diagnostics))
            Right scenarios -> do
              auditDay <-
                either die pure (resolveAuditDay compiled scenarios options)
              case runAudit compiled scenarios (cliScenarioName options) auditDay of
                Left err ->
                  die err
                Right auditResult ->
                  putStrLn (generateAuditReport compiled auditResult)

data CliOptions = CliOptions
  { cliInputPath :: Maybe FilePath
  , cliScenarioName :: Maybe String
  , cliAuditAt :: Maybe Day
  }

emptyCliOptions :: CliOptions
emptyCliOptions =
  CliOptions
    { cliInputPath = Nothing
    , cliScenarioName = Nothing
    , cliAuditAt = Nothing
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
