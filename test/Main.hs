{-# LANGUAGE CPP #-}

module Main ( main ) where

import           Control.Monad        ( mplus, mzero )
import           Control.Monad.Search

import           Data.Semigroup       as Sem

#if MIN_VERSION_tasty_hspec(1,1,7)
import           Test.Hspec
#endif

import           Test.Tasty
import           Test.Tasty.Hspec

data Side = L | R
    deriving (Eq, Show)

newtype C = C Int
    deriving (Eq, Ord, Show)

instance Sem.Semigroup C where
    (C l) <> (C r) = C (l + r)

instance Monoid C where
    mempty = C 0

#if !(MIN_VERSION_base(4,11,0))
    mappend = (<>)
#endif

testSearch :: Search C Side -> [(C, Side)]
testSearch = runSearch

testSearchIO :: SearchT C IO Side -> IO (Maybe (C, Side))
testSearchIO = runSearchBestT

infiniteSearch :: Monad m => SearchT C m Side
infiniteSearch = return L `mplus` (cost' (C 1) >> infiniteSearch)

spec :: IO TestTree
spec = testSpec "Control.Monad.Search" $ do
    it "Monad return generates one result" $
        testSearch (return L) `shouldBe` [ (C 0, L) ]

    it "MonadPlus mzero has no result" $
        testSearch mzero `shouldBe` []

    it "MonadPlus left identity law" $
        testSearch (mzero `mplus` return L) `shouldBe` [ (C 0, L) ]

    it "MonadPlus right identity law" $
        testSearch (return L `mplus` mzero) `shouldBe` [ (C 0, L) ]

    it "MonadPlus left distribution law" $
        testSearch (return L `mplus` return R) `shouldBe` [ (C 0, L), (C 0, R) ]

    it "Results are ordered by cost" $ do
        testSearch (return L `mplus` (cost' (C 1) >> return R))
            `shouldBe` [ (C 0, L), (C 1, R) ]
        testSearch ((cost' (C 1) >> return L) `mplus` return R)
            `shouldBe` [ (C 0, R), (C 1, L) ]

    it "Collapse suppresses results with higher cost" $
        testSearch ((collapse >> return L) `mplus` (cost' (C 1) >> return R))
            `shouldBe` [ (C 0, L) ]

    it "Collapse can be limited in scope" $
        testSearch (seal ((collapse >> return L) `mplus` (cost' (C 1) >> return R))
                    `mplus` (cost' (C 2) >> return R))
            `shouldBe` [ (C 0, L), (C 2, R) ]

    it "Results are generated lazily" $ do
        head (testSearch (return L `mplus`
                              (cost' (C 1) >> error "not lazy right")))
            `shouldBe` (C 0, L)
        head (testSearch ((cost' (C 1) >> error "not lazy left") `mplus`
                              return R))
            `shouldBe` (C 0, R)

    it "Results are generated lazily (infinite)" $
        head (testSearch infiniteSearch)
            `shouldBe` (C 0, L)

    it "Results are generated in constant space / linear time" $
        testSearch infiniteSearch !! 10000
            `shouldBe` (C 10000, L)

    it "Results are generated lazily in IO" $ do
        testSearchIO (return L `mplus`
                         (cost' (C 1) >> error "not lazy right"))
            `shouldReturn` Just (C 0, L)
        testSearchIO ((cost' (C 1) >> error "not lazy left") `mplus`
                         return R)
                `shouldReturn` Just (C 0, R)

    it "Results are generated lazily in IO (infinite)" $
        testSearchIO infiniteSearch
            `shouldReturn` Just (C 0, L)

main :: IO ()
main = do
    spec' <- spec
    defaultMain spec'
