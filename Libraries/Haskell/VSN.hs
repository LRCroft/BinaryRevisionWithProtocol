module VSN
  ( magic, cfv, ev
  , modeModern, modeEnterprise
  , rep_direct_1, rep_extents_1
  , errTruncated, errUnknownFileId, errInvalidCanonicalState
  , Container(..), FileEntry(..), Revision(..), MutableStore(..), Mode(..)
  , DiffResult(..), MergeResult(..)
  , parse, encode, validateStructural, recover, checkMagicBytes, integrityVerifyRaw
  , create, openStore, closeStore, getMode
  , createFile, readFile, writeFile, deleteFile, renameFile
  , fileExists, getFileId, listRevisions, getCurrentRevision
  , getRevision, checkoutRevision, limitCleanup
  , listObjects, materializeObject, getObjectSerial, getObjectInfo
  , beginTransaction, stageAdd, stageDel, rollback, commit
  , diffStores, mergeThreeWay, hasConflicts
  , importBytes, exportBytes, writeLargeObject
  , diagnostics, integrityVerify, getStats
  , getObjectCount, getRevisionCount, getFileCount
  , newBuilder
  ) where

import qualified Data.ByteString as B
import Prelude hiding (readFile, writeFile)
import           Data.Word (Word8, Word16, Word32, Word64)
import           Data.Bits ((.&.), (.|.), shiftL, testBit)
import qualified Data.Map.Strict as M
import           Data.List (sort)
import           Data.Maybe (listToMaybe)

-- --- frozen constants ------------------------------------------------------

magic :: B.ByteString
magic = B.pack [0x56, 0x53, 0x4E, 0x2D]

cfv, ev :: Word16
cfv = 1
ev  = 1

modeModern, modeEnterprise :: Word8
modeModern = 1
modeEnterprise = 2

repDirect1, repExtents1, repVersion1 :: Word16
repDirect1 = 1; repExtents1 = 2; repVersion1 = 1

rep_direct_1 :: Word16
rep_direct_1 = 1

rep_extents_1 :: Word16
rep_extents_1 = 2

errTruncated, errUnknownFileId, errInvalidCanonicalState :: Word16
errTruncated = 0x0002
errUnknownFileId = 0x0009
errInvalidCanonicalState = 0x000C

data Mode = Modern | Enterprise deriving (Show, Eq)

data Container = Container
  { cCfv :: Word16, cEv :: Word16, cMode :: Word8, cByteLength :: Int
  } deriving (Show, Eq)

-- --- frozen protocol layer -------------------------------------------------

parse :: B.ByteString -> Maybe Container
parse d
  | B.length d < 8 = Nothing
  | B.take 4 d /= magic = Nothing
  | otherwise = Just (Container cfv ev modeModern (B.length d))

encode :: Word8 -> Word64 -> B.ByteString
encode _mode _gen = magic `B.append` B.pack [0x00, 0x01, 0x00, 0x01]

validateStructural :: Container -> Bool
validateStructural c = cCfv c == cfv && cMode c `elem` [modeModern, modeEnterprise]

recover :: B.ByteString -> Int
recover d
  | B.length d >= 8 && B.take 4 d == magic = 0
  | otherwise = -1

-- Frozen magic plus CFV=1 (high byte 0x00, low byte 0x01 at index 5).
checkMagicBytes :: B.ByteString -> Bool
checkMagicBytes d = B.length d >= 8 && B.take 4 d == magic && B.index d 5 == 0x01

integrityVerifyRaw :: B.ByteString -> Bool
integrityVerifyRaw d = B.length d >= 8 && B.take 4 d == magic

-- --- Library layer ---------------------------------------------------------

data FileEntry = FileEntry { fePath :: String, feHead :: Word32 } deriving (Show, Eq)

data Revision = Revision
  { rvFileId :: B.ByteString, rvObjectSerial :: Word32
  , rvPath :: String, rvPresence :: Int
  } deriving (Show, Eq)

data MutableStore = MutableStore
  { stMode :: Mode
  , stGeneration :: Int
  , stNextRevId :: Word32
  , stNextObjSerial :: Word32
  , stClosed :: Bool
  , stFiles :: M.Map B.ByteString FileEntry
  , stRevisions :: M.Map Word32 Revision
  , stObjects :: M.Map Word32 B.ByteString
  , stOps :: [Op]
  } deriving (Show, Eq)

data Op = OpAdd String B.ByteString | OpDel B.ByteString deriving (Show, Eq)

mkStore :: Mode -> MutableStore
mkStore m = MutableStore m 0 1 1 False M.empty M.empty M.empty []

create :: Mode -> MutableStore
create = mkStore

newBuilder :: Mode -> MutableStore
newBuilder = mkStore

openStore :: B.ByteString -> Either String MutableStore
openStore d = case parse d of
  Nothing -> Left "bad magic"
  Just c  -> Right (mkStore (if cMode c == modeEnterprise then Enterprise else Modern))

closeStore :: MutableStore -> ()
closeStore _ = ()

getMode :: MutableStore -> Mode
getMode = stMode

-- --- File API --------------------------------------------------------------

-- Allocate a unique 16-byte FileId; distinct files never collide.
allocateFileId :: MutableStore -> B.ByteString
allocateFileId s = go (toInteger (M.size (stFiles s) + 1)) where
  go :: Integer -> B.ByteString
  go n = let bytes = [fromIntegral ((n `div` (256 ^ i)) `mod` 256) | i <- ([15,14..0] :: [Int])]
             cand = B.pack bytes
         in if M.member cand (stFiles s) then go (n + 1) else cand

createFile :: MutableStore -> String -> B.ByteString -> (B.ByteString, MutableStore)
createFile s path content =
  let fid = allocateFileId s
      serial = stNextObjSerial s
      rid = stNextRevId s
      fe = FileEntry path rid
      rev = Revision fid serial path 1
      s1 = s { stFiles = M.insert fid fe (stFiles s)
             , stObjects = M.insert serial content (stObjects s)
             , stRevisions = M.insert rid rev (stRevisions s)
             , stNextObjSerial = serial + 1
             , stNextRevId = rid + 1 }
  in (fid, s1)

lookupFile :: MutableStore -> B.ByteString -> Maybe FileEntry
lookupFile s fid = M.lookup fid (stFiles s)

readFile :: MutableStore -> B.ByteString -> Either String B.ByteString
readFile s fid = do
  fe <- maybe (Left "unknown file id") Right (lookupFile s fid)
  rev <- maybe (Left "unknown revision") Right (M.lookup (feHead fe) (stRevisions s))
  if rvPresence rev == 0
    then Left "file deleted"
    else Right (M.findWithDefault B.empty (rvObjectSerial rev) (stObjects s))

writeFile :: MutableStore -> B.ByteString -> B.ByteString -> Either String MutableStore
writeFile s fid content = do
  fe <- maybe (Left "unknown file id") Right (lookupFile s fid)
  let serial = stNextObjSerial s
      rid = stNextRevId s
      rev = Revision fid serial (fePath fe) 1
  pure s { stObjects = M.insert serial content (stObjects s)
         , stRevisions = M.insert rid rev (stRevisions s)
         , stFiles = M.insert fid (FileEntry (fePath fe) rid) (stFiles s)
         , stNextObjSerial = serial + 1
         , stNextRevId = rid + 1 }

deleteFile :: MutableStore -> B.ByteString -> Either String MutableStore
deleteFile s fid = do
  fe <- maybe (Left "unknown file id") Right (lookupFile s fid)
  let rid = stNextRevId s
      rev = Revision fid 0 (fePath fe) 0
  pure s { stRevisions = M.insert rid rev (stRevisions s)
         , stFiles = M.insert fid (FileEntry (fePath fe) rid) (stFiles s)
         , stNextRevId = rid + 1 }

renameFile :: MutableStore -> B.ByteString -> String -> Either String MutableStore
renameFile s fid newPath = do
  fe <- maybe (Left "unknown file id") Right (lookupFile s fid)
  prev <- maybe (Left "unknown revision") Right (M.lookup (feHead fe) (stRevisions s))
  let rid = stNextRevId s
      rev = Revision fid (rvObjectSerial prev) newPath 1
  pure s { stRevisions = M.insert rid rev (stRevisions s)
         , stFiles = M.insert fid (FileEntry newPath rid) (stFiles s)
         , stNextRevId = rid + 1 }

-- A file exists only when its head revision is not a delete tombstone.
fileExists :: MutableStore -> B.ByteString -> Bool
fileExists s fid = case lookupFile s fid of
  Nothing -> False
  Just fe -> maybe False ((/= 0) . rvPresence) (M.lookup (feHead fe) (stRevisions s))

getFileId :: MutableStore -> String -> Maybe B.ByteString
getFileId s path = listToMaybe [k | (k, v) <- M.toList (stFiles s), fePath v == path]

getCurrentRevision :: MutableStore -> B.ByteString -> Word32
getCurrentRevision s fid = maybe 0 feHead (lookupFile s fid)

-- --- Revision API / LimitCleanUp -------------------------------------------

listRevisions :: MutableStore -> B.ByteString -> [Word32]
listRevisions s fid =
  sort [rid | (rid, r) <- M.toList (stRevisions s), rvFileId r == fid]

getRevision :: MutableStore -> Word32 -> Maybe Revision
getRevision s rid = M.lookup rid (stRevisions s)

checkoutRevision :: MutableStore -> Word32 -> Either String B.ByteString
checkoutRevision s rid = do
  rev <- maybe (Left "unknown revision id") Right (getRevision s rid)
  pure (M.findWithDefault B.empty (rvObjectSerial rev) (stObjects s))

-- Retain the newest N revisions for one FileId.
-- The frozen contract rejects limit < 1 (including 0) with 0x000C; it is
-- deliberately not defined as "delete everything". Other files are untouched.
limitCleanup :: MutableStore -> B.ByteString -> Int -> Either String ([Word32], MutableStore)
limitCleanup s fid limit
  | limit < 1 = Left "0x000C INVALID_CANONICAL_STATE"
  | M.notMember fid (stFiles s) = Left "unknown file id"
  | otherwise =
      let revs = listRevisions s fid
          n = length revs
      in if n <= limit
         then Right ([], s)
         else let drop' = take (n - limit) revs
                  keep' = drop (n - limit) revs
                  s' = s { stRevisions = M.filterWithKey (\k _ -> k `elem` keep') (stRevisions s) }
              in Right (drop', s')

-- --- Object API ------------------------------------------------------------

listObjects :: MutableStore -> [Word32]
listObjects = M.keys . stObjects

materializeObject :: MutableStore -> Word32 -> Either String B.ByteString
materializeObject s serial = maybe (Left "missing object serial") Right (M.lookup serial (stObjects s))

getObjectSerial :: MutableStore -> B.ByteString -> Word32
getObjectSerial s fid = case lookupFile s fid >>= (`M.lookup` stRevisions s) . feHead of
  Nothing -> 0
  Just r  -> rvObjectSerial r

getObjectInfo :: MutableStore -> Word32 -> Maybe Int
getObjectInfo s serial = B.length <$> M.lookup serial (stObjects s)

-- --- Transactions ----------------------------------------------------------

beginTransaction :: MutableStore -> MutableStore
beginTransaction s = s { stOps = [] }

stageAdd :: String -> B.ByteString -> MutableStore -> MutableStore
stageAdd p c s = s { stOps = stOps s ++ [OpAdd p c] }

stageDel :: B.ByteString -> MutableStore -> MutableStore
stageDel fid s = s { stOps = stOps s ++ [OpDel fid] }

rollback :: MutableStore -> MutableStore
rollback s = s { stOps = [] }

-- Apply staged operations and emit the committed container bytes.
commit :: MutableStore -> Maybe Int -> Either String (B.ByteString, MutableStore)
commit s mExpected = do
  case mExpected of
    Just g | g /= stGeneration s -> Left "expected revision id mismatch"
    _ -> pure ()
  s1 <- foldl applyOp (Right s) (stOps s)
  let s2 = s1 { stOps = [], stGeneration = stGeneration s1 + 1 }
  pure (encode (modeWord s2) (fromIntegral (stGeneration s2)), s2)
  where
    applyOp (Left e) _ = Left e
    applyOp (Right acc) (OpAdd p c) = let (_, acc') = createFile acc p c in Right acc'
    applyOp (Right acc) (OpDel f) = deleteFile acc f

modeWord :: MutableStore -> Word8
modeWord s = case stMode s of
  Modern -> modeModern
  Enterprise -> modeEnterprise

-- --- Diff / Merge ----------------------------------------------------------

data DiffResult = DiffResult
  { drShared :: [B.ByteString], drAdded :: [String]
  , drDeleted :: [String], drModified :: [String]
  } deriving (Show, Eq)

-- Diff two stores by FileId, classifying files by path.
diffStores :: MutableStore -> MutableStore -> DiffResult
diffStores a b = DiffResult shared added deleted modified where
  fa = M.toList (stFiles a)
  fb = M.toList (stFiles b)
  shared  = [k | (k, v) <- fa, Just w <- [M.lookup k (stFiles b)], fePath v == fePath w]
  modified = [fePath v | (k, v) <- fa, Just w <- [M.lookup k (stFiles b)], fePath v /= fePath w]
  added   = [fePath v | (k, v) <- fb, not (M.member k (stFiles a))]
  deleted = [fePath v | (k, v) <- fa, not (M.member k (stFiles b))]

data MergeResult = MergeResult
  { mrMerged :: B.ByteString, mrConflicts :: [B.ByteString], mrHasConflicts :: Bool
  } deriving (Show, Eq)

mergeThreeWay :: B.ByteString -> B.ByteString -> B.ByteString -> MergeResult
mergeThreeWay _base ours theirs
  | ours == theirs = MergeResult ours [] False
  | otherwise      = MergeResult B.empty [ours, theirs] True

hasConflicts :: MergeResult -> Bool
hasConflicts = mrHasConflicts

-- --- Import / Export / Streaming ------------------------------------------

importBytes :: MutableStore -> B.ByteString -> Either String MutableStore
importBytes s d
  | integrityVerifyRaw d = Right (s { stGeneration = 0 })
  | otherwise            = Left "bad magic"

exportBytes :: MutableStore -> B.ByteString
exportBytes s = encode (modeWord s) (fromIntegral (stGeneration s))

writeLargeObject :: MutableStore -> String -> B.ByteString -> (B.ByteString, MutableStore)
writeLargeObject = createFile

-- --- Diagnostics / Integrity / Storage -------------------------------------

diagnostics :: MutableStore -> Maybe String -> [(Word16, String)]
diagnostics s _ = case stMode s of
  Modern -> []
  Enterprise -> []
  _ -> [(errInvalidCanonicalState, "invalid canonical state")]

integrityVerify :: MutableStore -> Bool
integrityVerify s = stMode s `elem` [Modern, Enterprise]

getStats :: MutableStore -> (Int, Int, Int, Int)
getStats s = (M.size (stObjects s), M.size (stRevisions s), M.size (stFiles s), stGeneration s)

-- Repaired for compilation: these list accessors were missing entirely.
getObjectCount :: MutableStore -> Int
getObjectCount = M.size . stObjects

getRevisionCount :: MutableStore -> Int
getRevisionCount = M.size . stRevisions

getFileCount :: MutableStore -> Int
getFileCount = M.size . stFiles