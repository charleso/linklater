{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}

module Toys.SummonPainting (summon) where

import           BasePrelude hiding ((&), putStrLn, lazy, words, intercalate)
import           Control.Lens hiding ((.=), re)
import           Data.Text (strip)
import qualified Network.Images.Search as Search
import           Text.Printf (printf)

import           Control.Monad.Except
import           Data.Aeson.Types
import           Data.Text.Strict.Lens
import           Text.Regex.PCRE.Heavy

import           Types
import           Utils

data Want = Want { _query :: !Text, _line :: !Line } deriving (Eq, Ord, Show)

line :: Lens' Want Line
line = lens _line (\Want{..} new -> Want _query new)

query :: Lens' Want Text
query = lens _query (\Want{..} new -> Want new _line)

parseTarget' :: Text -> [(Text, [Text])]
parseTarget' = scan [re|summon\s+painting\s+of\s+(.*)!|]

parseTarget :: Text -> Maybe Text
parseTarget = join . fmap listToMaybe . mapM (uncurry f) . parseTarget'
  where
    f :: Text -> [Text] -> Maybe Text
    f _ (query_ : _)=
      Just query_
    f _ [] =
      Nothing

instance FromJSON Want where
  parseJSON whole@(Object o) = do
    line_ <- parseJSON whole
    Just target_ <- parseTarget <$> o .: "text"
    return (Want target_ line_)

  parseJSON invalid =
    typeMismatch "Want" invalid

cleverlyReadFile :: FilePath -> IO Text
cleverlyReadFile filename =
  readFile filename <&> (^. (packed . to strip))

googleConfigIO :: IO Search.Gapi
googleConfigIO =
  Search.config <$> cleverlyReadFile "google-server-key" <*> cleverlyReadFile "google-search-engine-id"

google :: Want -> IO (Maybe Text)
google want = do
  urls <- Search.linksOfQuery <$> liftIO googleConfigIO <*> pure (want ^. query) >>= liftIO
  liftIO (sample urls)

alert :: Want -> Text -> Text
alert want =
  view packed . printf "<@%s> has summoned %s" (want ^. line . user)

naughty :: Text
naughty =
  "no results, or all your results were naughty ;)"

summon :: Chan Bytes -> Chan Speech -> IO ()
summon inbox outbox =
  withInbox inbox $ \want -> do
    maybeURL <- google want
    writeChan outbox (Speech (want ^. line) (maybe naughty (alert want) maybeURL))
