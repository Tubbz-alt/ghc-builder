
module ConfigHandler (configHandler) where

import ServerMonad

import Builder.Utils

import DynFlags
import GHC
import Linker
import MonadUtils
import Packages

import Control.Concurrent.MVar
import Control.Monad
import Data.Dynamic
import GHC.Paths

configHandler :: CHVar -> IO ()
configHandler chv = do m <- loadConfig
                       case m of
                           Just config -> worker chv config
                           Nothing -> die "Can't load config"

worker :: CHVar -> Config -> IO ()
worker chv config
 = do req <- takeMVar chv
      case req of
          ReloadConfig ->
              do m <- loadConfig
                 case m of
                     Just config' ->
                         worker chv config'
                     Nothing ->
                         do warn "Reloading config failed"
                            worker chv config
          GiveMeConfig mv ->
              do putMVar mv config
                 worker chv config

-- XXX Ought to catch exceptions, and return something more informative
-- than a Maybe type
loadConfig :: IO (Maybe Config)
loadConfig = do
    defaultErrorHandler defaultDynFlags $ do
      runGhc (Just libdir) $ do
        dflags0 <- getSessionDynFlags
        let dflags1 = dflags0 {
                          hscTarget = HscInterpreted
                      }
        setSessionDynFlags dflags1

        -- Due to the global nature of the linker, if we don't unload
        -- everything then the second time we call loadConfig we get
        -- a linker failure
        (dflags2, _) <- liftIO $ initPackages dflags1
        liftIO $ unload dflags2 []

        t <- guessTarget "Config.hs" Nothing
        setTargets [t]
        ok <- load LoadAllTargets
        case ok of
            Succeeded ->
                do modGraph <- getModuleGraph
                   loadedModSummaries <- filterM (isLoaded . ms_mod_name) modGraph
                   let loadedMods = map ms_mod loadedModSummaries
                   setContext [] loadedMods
            Failed ->
                error "XXX"
        d <- dynCompileExpr "config"
        case fromDynamic d of
            Just clients -> return (Just clients)
            Nothing -> return Nothing

