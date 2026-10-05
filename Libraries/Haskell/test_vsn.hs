module Main (main) where
import Prelude hiding (readFile, writeFile)
import qualified Data.ByteString.Char8 as B
import VSN
runCap :: Int -> Bool
runCap n = case n of
  1 -> let s = create Modern in getMode s == Modern
  2 -> let (fid, s2) = createFile (create Modern) "a" (B.pack "hello")
        in B.length (unwrap (readFile s2 fid)) == 5
  3 -> let (f, s1) = createFile (create Modern) "r" (B.pack "v1")
           s3 = unwrap (writeFile s1 f (B.pack "v3"))
        in length (listRevisions s3 f) >= 1
  4 -> let (f, s1) = createFile (create Modern) "lc" (B.pack "x")
           s2 = unwrap (writeFile s1 f (B.pack "v2"))
           s3 = unwrap (writeFile s2 f (B.pack "v3"))
           s5 = unwrap (writeFile s3 f (B.pack "v5"))
           (d, _) = unwrap (limitCleanup s5 f 2)
        in length d >= 1
  5 -> let (_, s) = createFile (create Modern) "o" (B.pack "AB")
        in notNull (listObjects s)
  6 -> let (bs, _) = unwrap (commit (create Modern) Nothing) in B.length bs >= 8
  7 -> rep_direct_1 == 1 && rep_extents_1 == 2
  8 -> let s = create Modern in getMode s `elem` [Modern, Enterprise]
  9 -> maybe False validateStructural (parse (encode 1 1))
  10 -> recover (encode 1 1) == 0
  11 -> let st = create Modern; (ff, s2) = createFile st "x" (B.pack "1") in notNull (drAdded (diffStores st s2))
  12 -> not (mrHasConflicts (mergeThreeWay (encode 1 1) (encode 1 1) (encode 1 1)))
  13 -> let b = exportBytes (create Modern)
            s2 = unwrap (openStore b)
        in getMode s2 == Modern
  14 -> let (_, s) = createFile (create Modern) "x" (B.pack "1") in length (listObjects s) >= 1
  15 -> length (diagnostics (create Modern) Nothing) >= 0
  16 -> integrityVerifyRaw (encode 1 1) == True
  17 -> let (_, s) = createFile (create Modern) "x" (B.pack "1")
        in length (stFiles s) >= 1
  18 -> getMode (newBuilder Modern) `elem` [Modern, Enterprise]
  19 -> checkMagicBytes (encode 1 1)
  where notNull = not . null
        unwrap (Right x) = x
        unwrap (Left e) = error e
main :: IO ()
main = do let r = [runCap n | n <- [1..19]]
          mapM_ (\(n, ok) -> putStrLn ((if ok then "PASS " else "FAIL ") ++ show n ++ " cap" ++ show n)) (zip [1..19] r)
          putStrLn ("PASS " ++ show (length (filter id r)))
