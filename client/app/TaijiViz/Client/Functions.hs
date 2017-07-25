{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE RecursiveDo           #-}
module TaijiViz.Client.Functions where

import qualified Data.Matrix.Unboxed            as MU
import qualified Data.Vector.Unboxed            as U
import qualified Data.Vector as V
import           Statistics.Sample (meanVarianceUnb)
import           Statistics.Function            (minMax)
import           Reflex.Dom.Core

import TaijiViz.Common.Types (RankTable(..))

scale :: U.Vector Double -> U.Vector Double
scale xs = U.map (\x -> (x - m) / sqrt v) xs
  where
    (m,v) = meanVarianceUnb xs

cv :: U.Vector Double -> Double
cv xs = sqrt v / m
  where
    (m,v) = meanVarianceUnb xs

maxFoldChange :: U.Vector Double -> Double
maxFoldChange xs = max' / min'
  where
    (min', max') = minMax xs

-- | Blend two colors
blend :: Double   -- ^ weight
      -> (Double, Double, Double)
      -> (Double, Double, Double)
      -> (Double, Double, Double)
blend w (r1,g1,b1) (r2,g2,b2) =
    ( r1 * w + r2 * (1 - w), g1 * w + g2 * (1 - w), b1 * w + b2 * (1 - w) )

-- | Filter RankTable by CV
filterRankTable :: (U.Vector Double -> Bool) -> RankTable -> RankTable
filterRankTable fn RankTable{..} = RankTable (V.fromList name) colNames
    (MU.fromRows rank) (MU.fromRows expr)
  where
    dat = zip3 (V.toList rowNames) (MU.toRows ranks) (MU.toRows expressions)
    (name, rank, expr) = unzip3 $ flip filter dat $ \(_, rank, _) -> fn rank

feedbackLoop :: MonadWidget t m
             => Event t a -> (Dynamic t Bool -> m (Event t b)) -> m (Dynamic t Bool)
feedbackLoop feedback fn = do
    rec evt <- fn canClick
        canClick <- holdUniqDyn =<< holdDyn True (leftmost [False <$ evt, True <$ feedback])
    return canClick
