module Compiler.Imports
  ( resolveImports
  ) where

import Compiler.AST
import Compiler.Parser (parseLawFile)
import Compiler.SymbolTable (Diagnostic(..))
import Data.List (nub)
import qualified Data.Set as S
import System.Directory (canonicalizePath, doesFileExist, getCurrentDirectory)
import System.FilePath ((</>), isAbsolute, takeDirectory)
import Text.Megaparsec (errorBundlePretty)

resolveImports :: SurfaceLawModuleAst -> IO (Either [Diagnostic] SurfaceLawModuleAst)
resolveImports rootModule = do
  cwd <- getCurrentDirectory
  resolvedForms <-
    resolveModuleGraph cwd [] S.empty rootModule
  pure $
    fmap
      (\(_, forms) ->
        rootModule
          { surfaceTopForms = forms
          }
      )
      resolvedForms

resolveModuleGraph
  :: FilePath
  -> [FilePath]
  -> S.Set FilePath
  -> SurfaceLawModuleAst
  -> IO (Either [Diagnostic] (S.Set FilePath, [Sourced TopFormAst]))
resolveModuleGraph cwd activeStack visited moduleAst = do
  canonicalModulePath <- canonicalizePath (surfaceLawPath moduleAst)
  if canonicalModulePath `elem` activeStack
    then
      pure
        (Left
          [ Diagnostic "import"
              ("cyclic import involving `" ++ canonicalModulePath ++ "`")
          ])
    else if S.member canonicalModulePath visited
      then pure (Right (visited, []))
      else do
        let localForms = surfaceTopForms moduleAst
            nonImportForms =
              [ topForm
              | topForm@(Sourced _ _ payload) <- localForms
              , not (isImportForm payload)
              ]
            importDecls =
              [ (sourcePath topForm, importDecl)
              | topForm@(Sourced _ _ payload) <- localForms
              , TopFormImport importDecl <- [payload]
              ]
            nextStack = canonicalModulePath : activeStack
            nextVisited = S.insert canonicalModulePath visited
        importedFormsResult <-
          resolveImportsInOrder cwd nextStack nextVisited importDecls
        pure
          (fmap
            (\(visitedAfterImports, importedForms) ->
              (visitedAfterImports, importedForms ++ nonImportForms))
            importedFormsResult)

resolveImportsInOrder
  :: FilePath
  -> [FilePath]
  -> S.Set FilePath
  -> [(FilePath, ImportDeclAst)]
  -> IO (Either [Diagnostic] (S.Set FilePath, [Sourced TopFormAst]))
resolveImportsInOrder _ _ visited [] = pure (Right (visited, []))
resolveImportsInOrder cwd activeStack visited ((importerPath, importDecl) : rest) = do
  resolvedPathResult <- resolveImportPath cwd importerPath (importPathAst importDecl)
  case resolvedPathResult of
    Left diagnostics -> pure (Left diagnostics)
    Right resolvedPath -> do
      importedModuleResult <- parseImportedModule resolvedPath
      case importedModuleResult of
        Left diagnostics -> pure (Left diagnostics)
        Right importedModule -> do
          currentFormsResult <- resolveModuleGraph cwd activeStack visited importedModule
          case currentFormsResult of
            Left diagnostics -> pure (Left diagnostics)
            Right (visitedAfterCurrent, currentForms) -> do
              restFormsResult <- resolveImportsInOrder cwd activeStack visitedAfterCurrent rest
              pure
                (fmap
                  (\(visitedAfterRest, restForms) ->
                    (visitedAfterRest, currentForms ++ restForms))
                  restFormsResult)

resolveImportPath :: FilePath -> FilePath -> FilePath -> IO (Either [Diagnostic] FilePath)
resolveImportPath cwd importerPath rawImportPath = do
  let candidates =
        if isAbsolute rawImportPath
          then [rawImportPath]
          else
            nub
              [ takeDirectory importerPath </> rawImportPath
              , cwd </> rawImportPath
              , cwd </> "lawlib" </> rawImportPath
              ]
  existingCandidates <- filterM doesFileExist candidates
  case existingCandidates of
    resolvedPath : _ -> Right <$> canonicalizePath resolvedPath
    [] ->
      pure
        (Left
          [ Diagnostic "import"
              ("could not resolve import `" ++ rawImportPath ++ "` from `" ++ importerPath ++ "`")
          ])

parseImportedModule :: FilePath -> IO (Either [Diagnostic] SurfaceLawModuleAst)
parseImportedModule inputPath = do
  input <- readFile inputPath
  pure $
    case parseLawFile inputPath input of
      Left bundle ->
        Left
          [ Diagnostic "import"
              ("failed to parse `" ++ inputPath ++ "`:\n" ++ errorBundlePretty bundle)
          ]
      Right surfaceModule ->
        Right surfaceModule

isImportForm :: TopFormAst -> Bool
isImportForm topForm =
  case topForm of
    TopFormImport _ -> True
    _ -> False

filterM :: Monad m => (a -> m Bool) -> [a] -> m [a]
filterM _ [] = pure []
filterM predicate (value : rest) = do
  includeValue <- predicate value
  remaining <- filterM predicate rest
  pure (if includeValue then value : remaining else remaining)
