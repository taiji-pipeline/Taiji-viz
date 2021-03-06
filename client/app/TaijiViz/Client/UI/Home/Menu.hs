{-# LANGUAGE RecursiveDo           #-}
{-# LANGUAGE OverloadedLists       #-}
{-# LANGUAGE OverloadedStrings     #-}
module TaijiViz.Client.UI.Home.Menu
    ( MenuEvent(..)
    , menu
    ) where

import           Control.Arrow             (second)
import Control.Monad (join)
import qualified Data.HashSet              as S
import qualified Data.Text                 as T
import           Reflex.Dom.Core           hiding (Delete)
import           Scientific.Workflow.Internal.Builder.Types (_note)
import qualified GHCJS.DOM.Types                as DOM
import Data.Default
import Taiji.Types (TaijiConfig)

import           TaijiViz.Client.Message
import           TaijiViz.Client.Types
import           TaijiViz.Client.Workflow  (NodeEvents (..), displayWorkflow)
import           TaijiViz.Common.Types
import TaijiViz.Client.UI.Home.Menu.Config

data MenuEvent t = MenuEvent
    { _menu_run     :: Event t Command
    , _menu_set_cwd :: Event t Command
    , _menu_delete  :: Event t Command
    }

menu :: MonadWidget t m
     => ServerResponse t
     -> Dynamic t (S.HashSet T.Text)
     -> m (MenuEvent t)
menu response@(ServerResponse result) selection = do
    divClass "ui fixed inverted menu small borderless" $ do
        divClass "item" $ elAttr "img" [("src", "favicon.ico")] $ return ()

        rec (runEvts, runBtnSt) <- handleMenuRun response config selection $
                domEvent Click runButton
            let (cwdEvts, canSetWD) = handleMenuSetWD runBtnSt (c, txt)
                (delEvts, canDelete) = handleDelete selection runBtnSt $
                    domEvent Click delButton

            -- Working directory
            (txt, c) <- divClass "item" $ divClass "ui action labeled input" $ do
                divClass "ui label" $ text "working directory:"
                let setTxt = flip fmapMaybe result $ \x -> case x of
                        CWD txt -> Just txt
                        _       -> Nothing
                txt <- textInput def{_textInputConfig_setValue=setTxt}
                let dynClass = flip fmap canSetWD $ \x -> case x of
                        True  -> "ui button"
                        False -> "ui button disabled"
                (e, _) <- elDynClass' "button" dynClass $ text "Refresh"
                return (_textInput_value txt, domEvent Click e)

            -- Run botton
            (runButton, _) <- elClass' "div" "item" $ dyn $ flip fmap runBtnSt $
                \st -> case st of
                    Disabled -> elClass "button" "disabled ui icon labeled button" $ do
                        elClass "i" "play icon" $ return ()
                        text "Run"
                    ShowRun -> elClass "button" "ui positive icon labeled button" $ do
                        elClass "i" "play icon" $ return ()
                        text "Run"
                    ShowStop -> elClass "button" "ui negative icon labeled button" $ do
                        elClass "i" "pause icon" $ return ()
                        text "Stop"
                    ShowLoad -> elClass "button" "ui loading button" $ text "Loading"

            -- Delete button
            (delButton, _) <- elClass' "div" "item" $ do
                let dynClass = flip fmap canDelete $ \x -> case x of
                        True  -> "ui button negative"
                        False -> "ui button negative disabled"
                elDynClass "button" dynClass $ text "Delete"

            (confBtn, _) <- divClass "right menu" $ elClass' "div" "item" $
                elClass "button" "ui button" $ text "Config"

            config <- uiModal (fmapMaybe (\x -> case x of
                Config c -> Just c
                _ -> Nothing ) result) (domEvent Click confBtn)

        return $ MenuEvent runEvts cwdEvts delEvts

data RunButtonState = ShowRun
                    | ShowStop
                    | ShowLoad
                    | Disabled
                    deriving (Eq)

-- | "Run" button handler.
-- Nothing: waiting for result
-- Just _ : result is available
handleMenuRun :: MonadWidget t m
              => ServerResponse t
              -> Dynamic t TaijiConfig
              -> Dynamic t (S.HashSet T.Text)
              -> Event t ()       -- when clicking the run button
              -> m (Event t Command, Dynamic t RunButtonState)
handleMenuRun (ServerResponse response) config clkNode menu_run = do
    st <- foldDynMaybe f Disabled $ leftmost [response', const ShowLoad <$> menu_run]
    let runEvt = attach (current config) $ tag (current clkNode) $
            ffilter (==ShowLoad) $ updated st
    return ((\(a, b) -> Run a $ S.toList b) <$> runEvt, st)
  where
    f ShowLoad Disabled = Nothing
    f ShowLoad ShowLoad = Nothing
    f new _             = Just new
    response' = flip fmapMaybe response $ \x -> case x of
        Gr _           -> Just ShowRun
        Status Running -> Just ShowStop
        Status Stopped -> Just ShowRun
        _              -> Nothing

-- | "Set CWD" handler
handleMenuSetWD :: Reflex t
                => Dynamic t RunButtonState
                -> (Event t (), Dynamic t T.Text)
                -> (Event t Command, Dynamic t Bool)
handleMenuSetWD runBtnSt (set_cwd, cwd) = (req, isAvailable)
  where
    isAvailable = flip fmap runBtnSt $ \st -> case st of
        Disabled -> True
        ShowRun  -> True
        ShowLoad -> False
        ShowStop -> False
    req = fmap SetCWD $ tag (current cwd) $ ffilter id $
        tag (current isAvailable) set_cwd

handleDelete :: Reflex t
             => Dynamic t (S.HashSet T.Text)
             -> Dynamic t RunButtonState
             -> Event t ()
             -> (Event t Command, Dynamic t Bool)
handleDelete selection runBtnSt evt = (req, isAvailable)
  where
    req = fmap (Delete . S.toList) $ tag (current selection) $ ffilter id $
        tag (current isAvailable) evt
    isAvailable = zipDynWith (&&) isStop $ fmap (not . S.null) selection
    isStop = flip fmap runBtnSt $ \st -> case st of
        Disabled -> True
        ShowRun  -> True
        ShowLoad -> False
        ShowStop -> False

uiModal :: MonadWidget t m => Event t TaijiConfig -> Event t ()
        -> m (Dynamic t TaijiConfig)
uiModal config evt = do
    pb <- delay 0 =<< getPostBuild
    (e, dynConfig) <- elClass' "div" "ui longer modal" $ do
        fmap join $ widgetHold (return def) $ fmap configPanel config
    performEvent_ (DOM.liftJSM . js_modalAction (_element_raw e) . const "" <$> pb)
    performEvent_ (DOM.liftJSM . js_modalAction (_element_raw e) . const "show" <$> evt)
    return dynConfig

foreign import javascript unsafe "$($1).modal($2);"
    js_modalAction :: DOM.Element -> DOM.JSString -> IO ()
