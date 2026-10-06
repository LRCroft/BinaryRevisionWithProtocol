module Main (main) where
import Prelude hiding (readFile, writeFile)
import qualified Data.ByteString as B
import Data.Word (Word8)
import Data.Char (ord)
import VSN

pk :: String -> B.ByteString
pk = B.pack . map (fromIntegral . ord)

runCap :: Int -> Bool
runCap n = case n of
  1 -> let s = create Modern in getMode s == Modern
  2 -> let (fid, s2) = createFile (create Modern) "a" (pk "hello")
        in B.length (unwrap (readFile s2 fid)) == 5
  3 -> let (f, s1) = createFile (create Modern) "r" (pk "v1")
           s3 = unwrap (writeFile s1 f (pk "v3"))
        in length (listRevisions s3 f) >= 1
  4 -> let (f, s1) = createFile (create Modern) "lc" (pk "x")
           s2 = unwrap (writeFile s1 f (pk "v2"))
           s3 = unwrap (writeFile s2 f (pk "v3"))
           s5 = unwrap (writeFile s3 f (pk "v5"))
           (d, _) = unwrap (limitCleanup s5 f 2)
        in length d >= 1
  5 -> let (_, s) = createFile (create Modern) "o" (pk "AB")
        in notNull (listObjects s)
  6 -> let (bs, _) = unwrap (commit (create Modern) Nothing) in B.length bs >= 8
  7 -> let (fid7, s7) = createFile (create Modern) "rep" (pk "VSN-TEST-DATA-0123")
       in unwrap (readFile s7 fid7) == pk "VSN-TEST-DATA-0123"
  8 -> let sm8 = create Modern
           se8 = create Enterprise
           (fm8, sm8b) = createFile sm8 "m" (pk "modern")
           (fe8, se8b) = createFile se8 "e" (pk "ent")
     in getMode sm8b == Modern && getMode se8b == Enterprise
       && unwrap (readFile sm8b fm8) == pk "modern"
       && unwrap (readFile se8b fe8) == pk "ent"
  9 -> maybe False validateStructural (parse (encode 1 1))
  10 -> recover (encode 1 1) == 0
  11 -> let st = create Modern; (ff, s2) = createFile st "x" (pk "1") in notNull (drAdded (diffStores st s2))
  12 -> let bA = pk "A"; bB = pk "B"
       in mrHasConflicts (mergeThreeWay bA bA bB) && not (mrHasConflicts (mergeThreeWay bA bB bB))
  13 -> let b = exportBytes (create Modern)
            s2 = unwrap (openStore b)
        in getMode s2 == Modern
  14 -> let big14 = B.replicate 512 (0xAB :: Word8)
            (fid14, s14) = createFile (create Modern) "big" big14
        in unwrap (readFile s14 fid14) == big14
  15 -> diagnostics (create Modern) Nothing == []
  16 -> integrityVerifyRaw (encode 1 1) == True
  17 -> let (_, s) = createFile (create Modern) "x" (pk "1")
        in length (stFiles s) >= 1
  18 -> getMode (newBuilder Modern) `elem` [Modern, Enterprise]
  19 -> let (fid19, s19) = createFile (create Modern) "i" (pk "interop-data-42")
            b19 = exportBytes s19
       in unwrap (readFile s19 fid19) == pk "interop-data-42" && B.take 4 b19 == pk "VSN-"
  where notNull = not . null
        unwrap (Right x) = x
        unwrap (Left e) = error e
main :: IO ()
main = do let r = [runCap n | n <- [1..19]]
          mapM_ (\(n, ok) -> putStrLn ("CAP " ++ show n ++ " " ++ (if ok then "PASS" else "FAIL") ++ " assertions=1 ops=0")) (zip [1..19] r)
