module Main where
import VSN
import qualified Data.ByteString as B
import Control.Monad (when)
import System.Exit

-- VSN independent consumer (Haskell) -- Storage Policy round-trip.
-- Uses the library's createWithPolicy + exportBytes (wire-out) + parse (wire-in).
hasSig :: B.ByteString -> Bool
hasSig b = any hit [0 .. hi]
  where
    ln = B.length b
    hi = max 0 (ln - 6)
    hit i = B.index b i == 0 && B.index b (i + 1) == 9 && B.index b (i + 2) == 4 &&
            B.index b (i + 3) == 9 && B.index b (i + 4) == 1 && B.index b (i + 5) == 1

main :: IO ()
main = do
  let cases = [(HIGHLY_VERTICAL, 1), (VERTICAL, 2),
               (HORIZONTAL, 3), (HIGHLY_HORIZONTAL, 4)]
  fails <- mapM (\(sp, v) ->
      let b = exportBytes (createWithPolicy sp)
          okSig = hasSig b
          got = case parse b of
                   Just c -> case cStoragePolicy c of
                               Just w -> fromIntegral w == v
                               Nothing -> False
                   Nothing -> False
      in do
            when (not okSig) (putStrLn "FAIL wire-out")
            when (not got) (putStrLn "FAIL wire-in")
            return (not (okSig && got))) cases
  if any id fails then do
    putStrLn "CONSUMER HASKELL FAIL"
    exitWith (ExitFailure 1)
  else
    putStrLn "CONSUMER HASKELL PASS"

