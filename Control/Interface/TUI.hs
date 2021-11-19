module Control.Interface.TUI where

import "transformers" Data.Functor.Reverse (Reverse (Reverse))
import "ansi-terminal" System.Console.ANSI (cursorUp, clearScreen)
import "pretty-terminal" System.Console.Pretty (Color (..), Style (Bold), style, bgColor, color)
import "base" Control.Monad (forever, void, when)
import "base" Data.Char (toLower)
import "base" Data.List (isInfixOf)
import "base" System.IO (Handle, BufferMode (NoBuffering), hReady, stdin, hSetBuffering)
import "sqlite-simple" Database.SQLite.Simple (Only (Only), open, query, query_, execute)
import "sqlite-simple" Database.SQLite.Simple.FromRow (FromRow (fromRow), field)
import "transformers" Control.Monad.Trans.Class (lift)
import "transformers" Control.Monad.Trans.State (StateT, evalStateT, get, modify, put)
import "vty" Graphics.Vty (Vty, Event (EvKey), Key (KEnter, KEsc, KBS, KUp, KDown, KChar), standardIOConfig, mkVty, update, picForImage, (<->), blue, defAttr, string, withBackColor, withForeColor, green, nextEvent, shutdown)

import Control.Objective (Objective (Objective))

data Zipper a = Zipper [a] a [a]

instance Functor Zipper where
	fmap f (Zipper bs x fs) = Zipper (f <$> bs) (f x) (f <$> fs)

focus :: Zipper a -> a
focus (Zipper _ x _) = x

up :: Zipper a -> Zipper a
up (Zipper [] x fs) = Zipper [] x fs
up (Zipper (b : bs) x fs) = Zipper bs b (x : fs)

down :: Zipper a -> Zipper a
down (Zipper bs x []) = Zipper bs x []
down (Zipper bs x (f : fs)) = Zipper (x : bs) f fs

filter_zipper :: (a -> Bool) -> Zipper a -> Maybe (Zipper a)
filter_zipper c (Zipper bs_ x fs_) = case (filter c bs_, c x, filter c fs_) of
	([], False, []) -> Nothing
	(b : bs, False, fs) -> Just $ Zipper bs b fs
	(bs, False, f : fs) -> Just $ Zipper bs f fs
	(bs, True, fs) -> Just $ Zipper bs x fs

print_zipper_items :: Show a => Zipper a -> IO ()
print_zipper_items (Zipper bs x fs) = void
	$ traverse (putStrLn . ("   " <>)) (Reverse $ show <$> bs)
		*> putStrLn (" * " <> show x) *> traverse (putStrLn . ("   " <>)) (show <$> fs)

handler :: Vty -> StateT (String, Zipper Objective) IO ()
handler vty = do
	lift clearScreen
	get >>= \(p, z) -> lift $ do
		when (not $ null p) $ putStrLn $ "Search for: " <> reverse p <> "\n"
		maybe (putStrLn "No such an objective...") print_zipper_items
			$ filter_zipper (\o -> isInfixOf (toLower <$> reverse p) $ toLower <$> show o) z
	lift $ cursorUp 11111
	lift (nextEvent vty) >>= \case
		EvKey KEsc _ -> pure ()
		EvKey KDown _ -> cursor_down *> handler vty
		EvKey KUp _ -> cursor_up *> handler vty
		EvKey (KChar x) _ -> type_pattern x *> handler vty
		EvKey KBS _ -> remove_last_char *> handler vty
		EvKey KEnter _ -> focused_view vty
		_ -> handler vty

-- It would be nice to have zoom (focus lens) here
focused_view :: Vty -> StateT (String, Zipper Objective) IO ()
focused_view vty = do
	snd <$> get >>= lift . putStrLn . (" " <>) . bgColor White . color Black . show . focus
	lift $ cursorUp 11111
	lift (nextEvent vty) >>= \case
		EvKey KEsc _ -> pure ()
		_ -> handler vty

cursor_up, cursor_down :: StateT (String, Zipper Objective) IO ()
cursor_up = modify $ \(p, z) -> (p, up z)
cursor_down = modify $ \(p, z) -> (p, down z)

type_pattern :: Char -> StateT (String, Zipper Objective) IO ()
type_pattern c = modify $ \(p, z) -> (c : p, z)

remove_last_char :: StateT (String, Zipper Objective) IO ()
remove_last_char = modify $ \(p, z) -> (if null p then p else tail p, z)
