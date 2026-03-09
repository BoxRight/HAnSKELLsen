module Main where

import Compiler.Compiler
import Compiler.Parser
import Logic (runExample)
import Pretty.PrettyReport (generateReport)
import System.Environment (getArgs)
import System.Exit (die)
import Text.Megaparsec (errorBundlePretty)

defaultInputPath :: FilePath
defaultInputPath = "lawlib/statutes/sales.dsl"

main :: IO ()
main = do
  args <- getArgs
  let inputPath =
        case args of
          [] -> defaultInputPath
          path : _ -> path
  input <- readFile inputPath
  case parseLawFile inputPath input of
    Left bundle ->
      die (errorBundlePretty bundle)
    Right lawModule ->
      case compileLawModule lawModule of
        Left diagnostics ->
          die (unlines (map show diagnostics))
        Right compiled -> do
          case compileInitialSystemState lawModule of
            Left diagnostics ->
              die (unlines (map show diagnostics))
            Right initialState -> do
              let finalState = runExample initialState
              putStrLn (generateReport compiled initialState finalState)
