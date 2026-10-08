module Main (main) where
import Prelude hiding (readFile, writeFile)
import qualified Data.ByteString as B
import Data.Word (Word8)
import Data.Char (ord)
import Data.Maybe (fromJust)
import VSN

pk :: String -> B.ByteString
pk = B.pack . map (fromIntegral . ord)

unwrap :: (Show a) => Either a b -> b
unwrap (Right x) = x
unwrap (Left e) = error ("unwrap failed: " ++ show e)

notNull :: [a] -> Bool
notNull = not . null

cap1 :: IO Bool
cap1 = return $ let s = create Modern in getMode s == Modern

cap2 :: IO Bool
cap2 = return $ let (fid, s2) = createFile (create Modern) "a" (pk "hello")
             in B.length (unwrap (readFile s2 fid)) == 5

cap3 :: IO Bool
cap3 = return $ let (f, s1) = createFile (create Modern) "r" (pk "v1")
                in length (listRevisions (unwrap (writeFile s1 f (pk "v3"))) f) >= 1

cap4 :: IO Bool
cap4 = return $ let (_, s1) = createFile (create Modern) "lc" (pk "x")
                    fid0 = fromJust (getFileId s1 "lc")
                    s2 = unwrap (writeFile s1 fid0 (pk "v2"))
                    s3 = unwrap (writeFile s2 fid0 (pk "v3"))
                    s4 = unwrap (writeFile s3 fid0 (pk "v5"))
                    (d, _) = unwrap (limitCleanup s4 fid0 2)
                in length d >= 1

cap5 :: IO Bool
cap5 = return $ let (_, s) = createFile (create Modern) "o" (pk "AB")
             in notNull (listObjects s)

cap6 :: IO Bool
cap6 = return $ let (bs, _) = unwrap (commit (create Modern) Nothing) in B.length bs >= 8

cap7 :: IO Bool
cap7 = return $ let (fid7, s7) = createFile (create Modern) "rep" (pk "VSN-TEST-DATA-0123")
                    in unwrap (readFile s7 fid7) == pk "VSN-TEST-DATA-0123"

cap8 :: IO Bool
cap8 = return $ let sm8 = create Modern; se8 = create Enterprise
                    (fm8, sm8b) = createFile sm8 "m" (pk "modern")
                    (fe8, se8b) = createFile se8 "e" (pk "ent")
                in getMode sm8b == Modern && getMode se8b == Enterprise
                   && unwrap (readFile sm8b fm8) == pk "modern"
                   && unwrap (readFile se8b fe8) == pk "ent"

cap9 :: IO Bool
cap9 = return $ maybe False validateStructural (parse (encode 1 1))

cap10 :: IO Bool
cap10 = return $ recover (encode 1 1) == 0

cap11 :: IO Bool
cap11 = let st = create Modern; (ff, s2) = createFile st "x" (pk "1")
        in return $ notNull (drAdded (diffStores st s2))

cap12 :: IO Bool
cap12 = let bA = pk "A"; bB = pk "B"; bC = pk "C"
        in return $ and [mrMerged (mergeThreeWay bA bA bA) == bA, not (mrHasConflicts (mergeThreeWay bA bA bA)),
                         mrMerged (mergeThreeWay bA bB bA) == bB, not (mrHasConflicts (mergeThreeWay bA bB bA)),
                         mrMerged (mergeThreeWay bA bA bB) == bB, mrMerged (mergeThreeWay bA bB bB) == bB,
                         mrHasConflicts (mergeThreeWay bA bB bC)]

cap13 :: IO Bool
cap13 = return $ let b = exportBytes (create Modern); s2 = unwrap (openStore b)
             in getMode s2 == Modern

cap14 :: IO Bool
cap14 = return $ let big14 = B.replicate 512 (0xAB :: Word8); (fid14, s14) = createFile (create Modern) "big" big14
                 in unwrap (readFile s14 fid14) == big14

cap15 :: IO Bool
cap15 = return $ diagnostics (create Modern) Nothing == []

cap16 :: IO Bool
cap16 = return $ integrityVerifyRaw (encode 1 1) == True

cap17 :: IO Bool
cap17 = return $ let (_, s) = createFile (create Modern) "x" (pk "1")
             in length (stFiles s) >= 1

cap18 :: IO Bool
cap18 = return $ getMode (newBuilder Modern) `elem` [Modern, Enterprise]

main :: IO ()
main = do
    -- Run caps 1-18
    rs <- sequence [cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8,
                    cap9, cap10, cap11, cap12, cap13, cap14, cap15,
                    cap16, cap17, cap18]
    -- Cap 19: read frozen vector and verify
    bs <- B.readFile "TestVectors/DIRECT-02.vsn"
    let ok19 = B.length bs == 414 && B.take 4 bs == magic &&
               case parse bs of { Nothing -> False; Just cont -> case openStore bs of
                    Left _ -> False; Right _ -> True }
    let allRs = rs ++ [ok19]
    mapM_ (\(n, ok) -> putStrLn ("CAP " ++ show n ++ " " ++ (if ok then "PASS" else "FAIL") ++ " assertions=1 ops=0")) (zip [1..19] allRs)
    let passed = length $ filter id allRs
        failed = length $ filter (not . id) allRs
    putStrLn ("PASSED=" ++ show passed ++ " FAILED=" ++ show failed)
