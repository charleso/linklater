{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- If writing Slack bots intrigues you, check out: https://github.com/hlian/linklater

import qualified Network.Images.Search as Search

import           Control.Monad.Except (throwError, liftIO, runExceptT)
import           Data.Aeson (encode)
import           Data.Text (strip)
import           Network.Wai.Handler.Warp (run)

import           Utils (sample)

-- Naked imports.
import           BasePrelude hiding (words, intercalate)
import           Control.Lens
import           Data.Text.Strict.Lens
import           Network.Linklater
import           Types

cleverlyReadFile :: FilePath -> IO Text
cleverlyReadFile filename =
  readFile filename <&> (^. (packed . to strip))

configIO :: IO Config
configIO =
  Config <$> cleverlyReadFile "hook"

googleConfigIO :: IO Search.Gapi
googleConfigIO =
  Search.config <$> cleverlyReadFile "google-server-key" <*> cleverlyReadFile "google-search-engine-id"

parseQuery :: Text -> JPEGMonad Text
parseQuery query = case strip query of
  "" -> throwError "Try again, friend. The syntax is /jpeg [query], where query is nonempty."
  x -> return x

messageOfCommand :: Command -> JPEGMonad Message
messageOfCommand (Command "jpeg" user_ channel_ (Just query)) = do
  urls <- (Search.linksOfQuery <$> liftIO googleConfigIO <*> parseQuery query) >>= liftIO
  maybeURL <- liftIO (sample urls)
  case maybeURL of
    Nothing ->
      throwError "no images found"
    Just url ->
      return (messageOf [FormatAt user_, FormatLink url url])
  where
    messageOf =
      FormattedMessage (EmojiIcon "gift") "jpgtobot" channel_
messageOfCommand _ =
  throwError "unrecognized command"

jpgto :: Command -> IO Text
jpgto command = do
  putStrLn ("+ Incoming command: " <> show command)
  config <- configIO
  message <- runExceptT (messageOfCommand command)
  case (debug, message) of
    (False, Right m) -> do
      putStrLn ("+ Outgoing message: " <> show (encode m))
      anEither <- runExceptT (say m config)
      case anEither of
        Left requestError ->
          putStrLn ("! Request error: " <> show requestError)
        Right () ->
          return ()
      return ""
    (False, Left errorMessage) ->
      return ("jpegbot encountered an error, is on fire now: " <> (errorMessage ^. packed))
    (True, Right m) -> do
      putStrLn ("+ Outgoing message: " <> show (encode m))
      return ""
    (True, Left errorMessage) -> do
      putStrLn ("! Outgoing ERROR: " <> errorMessage)
      return ""
  where
    debug = False

main :: IO ()
main = do
  putStrLn ("+ Listening on port " <> show port)
  run port (slashSimple jpgto)
    where
      port = 3333
