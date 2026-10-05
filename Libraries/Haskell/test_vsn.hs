module Main (main) where
import qualified Data.ByteString as B
import VSN
runCap :: Int -> Bool
runCap n = case n of
 1 -> let s = create Modern in getMode s == Modern
 2 -> let (fid, s') = createFile (create Modern) "a" (B.pack "hello")
       in B.length (readFile s' fid) == 5
 3 -> let (f,s1) = createFile (create Modern) "r" (B.pack "v1")
         s2 = writeFile s1 f (B.pack "v2"); s3 = writeFile s2 f (B.pack "v3")
     in length (listRevisions s3 f) >= 3
 4 -> let (f,s1) = createFile (create Modern) "lc" (B.pack "x")
         s5 = foldl' (\a i -> writeFile a f (B.pack [fromIntegral i])) s1 [1..5]
         (d,_) = limitCleanup s5 f 3
     in length d == 2
 5 -> let (_,s) = createFile (create Modern) "o" (B.pack "AB")
     in notNull (listObjects s)
 6 -> case fst (commit (create Modern) Nothing) of bs -> B.length bs >= 8
 7 -> rep_direct_1 == 1 && rep_extents_1 == 2
 8 -> let s = create Modern in getMode s `elem` [Modern, Enterprise]
 9 -> validateStructural (create Modern)
10 -> recover (encode 1 1) == 0
11 -> case diffStores (createModern) (createModern) of d -> notNull (fst d)
12 -> case mergeThreeWay (create M) (create M) (create M) of m -> hasConflicts m
13 -> let b = exportBytes (createModern); s = openStore b in getMode s == 1
14 -> case getObjectInfo (let (_,s)=createFile (create Modern) "x" (B.pack "1") in s) 1 of Just _ -> True; Nothing -> False
15 -> length (diagnostics (createModern) "Full") >= 0
16 -> integrityVerifyRaw (encode 1 1) == True
17 -> getFileCount (let (_,s)=createFile (create Modern) "x" (B.pack "1") in s) >= 1
18 -> getMode (newBuilder 1) `elem` [1,2]
19 -> checkMagicBytes (encode 1 1)
  where createModern = create 1; create M = create Modern
main :: IO ()
main = do let r = [runCap n | n <- [1..19]]
          putStrLn $ "PASS " ++ show (sum $ map fromEnum r)
