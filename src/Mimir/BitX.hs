{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Mimir.BitX(
    module Mimir.Std,
    module Mimir.BitX.Types
) where

import Mimir.Types
import Mimir.Std
import Mimir.BitX.Types
import Mimir.BitX.Instances

import Control.Lens (view)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson (ToJSON, encode)
import Data.Monoid
import Network.HTTP.Conduit (urlEncodedBody)
import Numeric (showFFloat)

instance Body BL.ByteString where
    encodeBody = id

instance HasManager BitX where
    getManager = view bxManager

instance Exchange BitX where
    type ExchangeM BitX = StdM BitX
    type ErrorT BitX = StdErr
    reifyIO = reifyStdM

---
--- Ticker
---

instance TickerP BitX where
    type TickerT BitX = Ticker
    ticker' _ = do
        url <- marketURL "ticker"
        req <- buildReq url "GET" [] noBody
        httpJSON req

---
--- Candles
---

instance CandlesP BitX where
    type CandleIntervalT BitX = CandleInterval
    type CandleT BitX = Candle
    candles' bx iv = do
        let pairCode = view bxPairCode bx
        let url = "https://bitx.co/ajax/1/candles?pair=" <> pairCode <> "&duration=" <> (show iv)
        req <- buildReq url "GET" [] noBody
        (PriceHistory cx) <- httpJSON req
        return cx

---
--- OrderBook
---

instance OrderBookP BitX where
    type OrderBookT BitX = OrderBook
    orderBook' _ = do
        url <- marketURL "orderbook"
        req <- buildReq url "GET" [] noBody
        httpJSON req

---
--- TradeHistory
---

instance TradeHistoryP BitX where
    type TradeT BitX = Trade
    tradeHistory' _ = do
        url <- marketURL "trades"
        req <- buildReq url "GET" [] noBody
        (TradeHistory tx) <- httpJSON req
        return tx

---
--- Spot
---

instance SpotP BitX where
    type SpotBalancesT BitX = Balances
    type SpotOrderTypeT BitX = OrderType
    type SpotOrderAmountT BitX = Double
    type SpotOrderT BitX = Order
    type SpotOrderIDT BitX = String
    spotBalances' _ = do
        url <- marketURL "balance"
        req <- buildReq url "GET" [] noBody
        (Accounts ax) <- httpJSON req
        toBalances ax
    currentSpotOrders' _ = do
        bURL <- marketURL "listorders"
        req <- buildReq (bURL <> "&state=PENDING") "GET" [] noBody
        (Orders mox) <- httpJSON req
        maybe (return []) return mox
    placeLimitSpotOrder' _ typ vol price = do
        bURL <- viewStdM bxBaseURL
        params <- mkLimitOrder typ vol price
        req <- fmap (urlEncodedBody params) $ buildReq (bURL <> "postorder") "POST" [] noBody
        (OrderResponse oid) <- httpJSON req
        return oid
    placeMarketSpotOrder' _ typ amount = do
        bURL <- viewStdM bxBaseURL
        params <- mkMarketOrder typ amount
        req <- fmap (urlEncodedBody params) $ buildReq (bURL <> "marketorder") "POST" [] noBody
        (OrderResponse oid) <- httpJSON req
        return oid
    cancelSpotOrder' _ oid = do
        bURL <- viewStdM bxBaseURL
        req <- fmap (urlEncodedBody [("order_id", B.pack $ oid)]) $ buildReq (bURL <> "stoporder") "POST" [] noBody
        http' req

---
--- Utility
---

toBalances :: [Account] -> StdM BitX Balances
toBalances ax = do
    currencyCode <- viewStdM bxCurrencyCode
    commodityCode <- viewStdM bxCommodityCode
    let currency = sum . fmap (\a -> _acBalance a - _acReserved a) . filter ((==currencyCode) . view acAssetCode) $ ax
    let commodity = sum . fmap (\a -> _acBalance a - _acReserved a) . filter ((==commodityCode) . view acAssetCode) $ ax
    return $ Balances currency commodity

marketURL :: String -> StdM BitX String
marketURL endpoint = do
    baseURL <- viewStdM bxBaseURL
    pairCode <- viewStdM bxPairCode
    let url = baseURL <> endpoint <> "?pair=" <> pairCode
    return url

mkLimitOrder :: OrderType -> Double -> Double -> StdM BitX [(B.ByteString, B.ByteString)]
mkLimitOrder typ vol price = do
    pairCode <- viewStdM bxPairCode
    return [("pair", B.pack pairCode), ("type", B.pack $ show typ), ("volume", encNum $ vol), ("price", encNum $ price)]

mkMarketOrder :: OrderType -> Double -> StdM BitX [(B.ByteString, B.ByteString)]
mkMarketOrder typ amount = do
    pairCode <- viewStdM bxPairCode
    case typ of
        BID -> return [("pair", B.pack pairCode), ("type", "BUY"), ("counter_volume", encNum amount)]
        ASK -> return [("pair", B.pack pairCode), ("type", "SELL"), ("base_volume", encNum amount)]

encNum :: Double -> B.ByteString
encNum n = B.pack $ showFFloat (Just 6) n ""

noBody :: Maybe BL.ByteString
noBody = Nothing
