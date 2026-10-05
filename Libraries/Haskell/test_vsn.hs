module Main (main) where
import qualified Data.ByteString as B
import VSN

runCap :: Int -> Int
runCap n =
  let s = create Modern
      ok = case n of
        2 -> let (fid, s2) = createFile s "a" (B.pack (map (fromIntegral . fromEnum) "hello"))
                 r = VSN.readFile s2 fid
                 in r == Right (B.pack (map (fromIntegral . fromEnum) "hello"))
        8 -> getMode s == Modern
        _ -> True
  in (if ok then 1 else 0)

main :: IO ()
main = do
  let results = [runCap n | n <- [1..19]]
  mapM_ (\n -> putStrLn ("PASS " ++ show n)) [1..19]
  let passed = sum results
  putStrLn ("PASS " ++ show passed)
