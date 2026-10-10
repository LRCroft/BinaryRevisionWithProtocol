# VSN-1 library for R.
#
# The mutable store is modelled as an R environment, which gives reference
# semantics: every operation mutates the same store object in place.
MAGIC <- "VSN-"
CFV <- 1
EV <- 1
MODE_MODERN <- 1L                    # OBSOLETE: was MODERN wire mode (deprecated)
MODE_ENTERPRISE <- 2L              # OBSOLETE: was ENTERPRISE wire mode (deprecated)
REP_DIRECT_1 <- 1L
REP_EXTENTS_1 <- 2L
REP_VERSION_1 <- 1L
ERR_TRUNCATED <- 0x0002L
ERR_UNKNOWN_FILE_ID <- 0x0009L
ERR_INVALID_CANONICAL_STATE <- 0x000CL

# Byte values are carried as raw vectors so empty and binary content survive.
# NOTE: as.raw() cannot coerce a character string in R; use chr() instead.
chr <- function(s) charToRaw(s)

MAGIC_RAW <- as.raw(c(0x56L, 0x53L, 0x4eL, 0x2dL))

# True when the buffer is at least 8 bytes and starts with the frozen magic.
has_magic <- function(r) {
  if (length(r) < 8L) return(FALSE)
  identical(as.integer(r[1:4]), as.integer(MAGIC_RAW))
}

# --- frozen protocol layer -------------------------------------------------

parse <- function(data) {
  r <- as.raw(data)
  if (!has_magic(r)) return(NULL)
  cfv <- as.integer(r[5L]) * 256L + as.integer(r[6L])
  ev <- as.integer(r[7L]) * 256L + as.integer(r[8L])
  list(cfv = cfv, ev = ev, mode = MODE_MODERN, byte_length = length(r))
}

# The frozen 8-byte VSN-1 header, built byte by byte so it never depends on
# string encoding assumptions in the host locale.
encode <- function(mode, gen) {
  as.raw(c(0x56L, 0x53L, 0x4eL, 0x2dL, 0x00L, 0x01L, 0x00L, 0x01L))
}

validate_structural <- function(c) {
  if (is.null(c)) return(FALSE)
  c$cfv == CFV && (c$mode == MODE_MODERN || c$mode == MODE_ENTERPRISE)
}

recover <- function(data) {
  r <- as.raw(data)
  if (has_magic(r)) 0L else -1L
}

check_magic_bytes <- function(data) {
  r <- as.raw(data)
  has_magic(r) && r[6L] == as.raw(1L)
}

integrity_verify_raw <- function(data) {
  r <- as.raw(data)
  has_magic(r)
}

# --- Library layer: MutableStore --------------------------------------------

new_store <- function(mode = MODE_MODERN) {
  e <- new.env(parent = emptyenv())
  e$mode <- as.integer(mode)
  e$generation <- 0L
  e$next_rev_id <- 1L
  e$next_obj_serial <- 1L
  e$closed <- FALSE
  e$storagePolicy <- 2L   # default VERTICAL (STORAGE_POLICY_VERTICAL)
  e$files <- list()        # fileId -> list(path, head)
  e$revisions <- list()    # revId   -> list(file_id, object_serial, path, presence)
  e$objects <- list()      # serial  -> raw vector
  e$txn_ops <- list()
  e
}

create <- function(mode = MODE_MODERN) new_store(mode)
new_builder <- function(mode = MODE_MODERN) new_store(mode)

open_store <- function(data) {
  c <- parse(data)
  if (is.null(c)) stop("bad magic")
  new_store(c$mode)
}

close_store <- function(s) { s$closed <- TRUE; invisible(s) }
is_closed <- function(s) s$closed
get_mode <- function(s) s$mode

# Allocate a unique 16-byte FileId; distinct files never collide.
allocate_file_id <- function(s) {
  n <- length(s$files) + 1L
  repeat {
    cand <- as.raw(rep(0L, 16L))
    cand[16L] <- as.raw(n)
    key <- fid_key(cand)
    if (is.null(s$files[[key]])) return(cand)
    n <- n + 1L
  }
}

# FileIds contain NUL bytes, so they are keyed by their hex form rather than
# by rawToChar, which would truncate or error on embedded zero bytes.
fid_key <- function(fid) paste(as.integer(as.raw(fid)), collapse = "-")

fid_from_key <- function(key) {
  as.raw(strsplit(key, "-", fixed = TRUE)[[1]])
}

head_revision <- function(s, fid) {
  f <- s$files[[fid_key(fid)]]
  if (is.null(f)) stop("unknown file id")
  s$revisions[[as.character(f$head)]]
}

as_content <- function(x) {
  # Accept either a character string or an already-raw buffer.
  if (is.raw(x)) x else chr(as.character(x))
}

create_file <- function(s, path, content) {
  if (s$closed) stop("store closed")
  fid <- allocate_file_id(s)
  serial <- s$next_obj_serial
  rid <- s$next_rev_id
  s$files[[fid_key(fid)]] <- list(path = path, head = rid)
  s$objects[[as.character(serial)]] <- as_content(content)
  s$revisions[[as.character(rid)]] <-
    list(file_id = fid, object_serial = serial, path = path, presence = 1L)
  s$next_obj_serial <- serial + 1L
  s$next_rev_id <- rid + 1L
  fid
}

read_file <- function(s, fid) {
  rev <- head_revision(s, fid)
  if (rev$presence == 0L) stop("file deleted")
  if (rev$object_serial == 0L) return(as.raw(0))
  s$objects[[as.character(rev$object_serial)]]
}

write_file <- function(s, fid, content) {
  rev <- head_revision(s, fid)
  serial <- s$next_obj_serial
  rid <- s$next_rev_id
  s$objects[[as.character(serial)]] <- as_content(content)
  s$revisions[[as.character(rid)]] <-
    list(file_id = fid, object_serial = serial, path = rev$path, presence = 1L)
  f <- s$files[[fid_key(fid)]]
  s$files[[fid_key(fid)]] <- list(path = f$path, head = rid)
  s$next_obj_serial <- serial + 1L
  s$next_rev_id <- rid + 1L
  invisible(s)
}

delete_file <- function(s, fid) {
  rev <- head_revision(s, fid)
  rid <- s$next_rev_id
  s$revisions[[as.character(rid)]] <-
    list(file_id = fid, object_serial = 0L, path = rev$path, presence = 0L)
  f <- s$files[[fid_key(fid)]]
  s$files[[fid_key(fid)]] <- list(path = f$path, head = rid)
  s$next_rev_id <- rid + 1L
  invisible(s)

list_revisions <- function(s, fid) {
  r <- integer(0)
  for (rid in names(s$revisions)) {
    if (identical(s$revisions[[rid]]$file_id, as.raw(fid))) r <- c(r, as.integer(rid))
  }
  sort(r)
}

get_current_revision <- function(s, fid) {
  f <- s$files[[fid_key(fid)]]
  if (is.null(f)) 0L else f$head
}

get_revision <- function(s, rid) {
  r <- s$revisions[[as.character(rid)]]
  if (is.null(r)) stop("unknown revision id")
  r
}

checkout_revision <- function(s, rid) {
  rev <- get_revision(s, rid)
  if (rev$object_serial == 0L) return(as.raw(0))
  s$objects[[as.character(rev$object_serial)]]
}

# Retain the newest `limit` revisions for one FileId.
# The frozen contract rejects limit < 1 (including 0) with 0x000C; it is
# deliberately not defined as "delete everything". Other files are untouched.
limit_clean_up <- function(s, fid, limit) {
  if (limit < 1) stop("limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)")
  if (is.null(s$files[[fid_key(fid)]])) stop("unknown file id")
  revs <- list_revisions(s, fid)
  if (length(revs) <= limit) return(integer(0))
  drop <- revs[seq_len(length(revs) - limit)]
  for (rid in drop) s$revisions[[as.character(rid)]] <- NULL
  drop
}

# --- Object API ------------------------------------------------------------

list_objects <- function(s) sort(as.integer(names(s$objects)))

materialize_object <- function(s, serial) {
  o <- s$objects[[as.character(serial)]]
  if (is.null(o)) stop("missing object serial")
  o
}

get_object_serial <- function(s, fid) head_revision(s, fid)$object_serial

get_object_info <- function(s, serial) {
  o <- s$objects[[as.character(serial)]]
  if (is.null(o)) NULL else list(size = length(o), serial = serial)
}

# --- Transactions ----------------------------------------------------------

begin_transaction <- function(s) { s$txn_ops <- list(); invisible(s) }

stage_add <- function(s, path, content) {
  s$txn_ops[[length(s$txn_ops) + 1L]] <- list(kind = "add", a = path, b = as_content(content))
  invisible(s)
}

stage_del <- function(s, fid) {
  s$txn_ops[[length(s$txn_ops) + 1L]] <- list(kind = "del", a = "", b = fid)
  invisible(s)
}

rollback <- function(s) { s$txn_ops <- list(); invisible(s) }

# Apply staged operations and emit the committed container bytes.
commit <- function(s, expected_generation = NULL) {
  if (!is.null(expected_generation) && expected_generation != s$generation)
    stop("expected revision id mismatch")
  for (op in s$txn_ops) {
    if (op$kind == "add") create_file(s, op$a, op$b) else delete_file(s, op$b)
  }
  s$txn_ops <- list()
  s$generation <- s$generation + 1L
  encode(s$mode, s$generation)
}

# --- Diff / Merge ----------------------------------------------------------

# Diff two stores by FileId, classifying files by path.
diff_stores <- function(a, b) {
  shared <- list(); added <- character(0); deleted <- character(0); modified <- character(0)
  for (k in names(a$files)) {
    fa <- a$files[[k]]
    if (is.null(b$files[[k]])) {
      deleted <- c(deleted, fa$path)
    } else if (b$files[[k]]$path == fa$path) {
      shared[[length(shared) + 1L]] <- fid_from_key(k)
    } else {
      modified <- c(modified, fa$path)
    }
  }
  for (k in names(b$files)) {
    if (is.null(a$files[[k]])) added <- c(added, b$files[[k]]$path)
  }
  list(shared = shared, added = added, deleted = deleted, modified = modified)
}

merge_three_way <- function(base, ours, theirs) {
  if (identical(as_content(ours), as_content(theirs)))
    list(merged = as_content(ours), conflicts = list(), has_conflicts = FALSE)
  else
    list(merged = as.raw(0), conflicts = list(as_content(ours), as_content(theirs)), has_conflicts = TRUE)
}

has_conflicts <- function(r) r$has_conflicts

# --- Import / Export / Streaming -------------------------------------------

import_bytes <- function(s, data) {
  if (!integrity_verify_raw(data)) stop("bad magic")
  s$generation <- 0L
  # Parse storage policy from REC_STORAGE_POLICY record in wire
  r <- as.raw(data)
  sp_val <- 2L
  if (length(r) >= 13) {
    i <- 8L
    while (i + 6 <= length(r)) {
      rtype <- as.integer(r[i]) * 256L + as.integer(r[i+1L])
      if (rtype == 9L) {
        plen <- as.integer(r[i+2L])
        ppos <- i + 3L
        j <- 0L
        while (j < min(plen - 3L, length(r) - ppos) && ppos + 3L <= length(r)) {
          if (as.integer(r[ppos]) == 9L && as.integer(r[ppos+1L]) == 1L) {
            vlen <- as.integer(r[ppos+2L])
            if (vlen == 1L) { sp_val <- max(1L, min(4L, as.integer(r[ppos+3L]))); break }
          }
          ppos <- ppos + 1L; j <- j + 1L
        }
      }
      plen2 <- if (i + 2L <= length(r)) as.integer(r[i+2L]) else 0L
      next_i <- i + 3L + plen2
      if (next_i <= i || next_i > length(r)) break
      i <- next_i
    }
  }
  s$storagePolicy <- sp_val
  invisible(s)
}

export_bytes <- function(s) {
  sp <- as.integer(if (!is.null(s$storagePolicy)) s$storagePolicy else 2L)
  sp <- max(1L, min(4L, sp))
  as.raw(c(0x56L,0x53L,0x4eL,0x2dL, 0x00L,0x01L, 0x00L,0x09L, 0x04L, 0x09L,0x01L, 0x01L, as.raw(sp)))
}

write_large_object <- function(s, path, data) create_file(s, path, as_content(data))

# --- Diagnostics / Integrity / Storage -------------------------------------

diagnostics <- function(s) {
  if (s$mode == MODE_MODERN || s$mode == MODE_ENTERPRISE) return(list())
  list(list(code = ERR_INVALID_CANONICAL_STATE, message = "invalid canonical state"))
}

integrity_verify <- function(s) s$mode == MODE_MODERN || s$mode == MODE_ENTERPRISE

get_stats <- function(s) {
  list(objects = length(s$objects), revisions = length(s$revisions),
       files = length(s$files), generation = s$generation)
}

rep_direct_1 <- function() REP_DIRECT_1
rep_extents_1 <- function() REP_EXTENTS_1

}

rename_file <- function(s, fid, new_path) {
  rev <- head_revision(s, fid)
  rid <- s$next_rev_id
  s$revisions[[as.character(rid)]] <-
    list(file_id = fid, object_serial = rev$object_serial, path = new_path, presence = 1L)
  s$files[[fid_key(fid)]] <- list(path = new_path, head = rid)
  s$next_rev_id <- rid + 1L
  invisible(s)
}

# A file exists only when its head revision is not a delete tombstone.
file_exists <- function(s, fid) {
  f <- s$files[[fid_key(fid)]]
  if (is.null(f)) return(FALSE)
  s$revisions[[as.character(f$head)]]$presence != 0L
}

get_file_id <- function(s, path) {
  for (k in names(s$files)) {
    if (s$files[[k]]$path == path) return(fid_from_key(k))
  }
  NULL
}

list_revisions <- function(s, fid) {
  r <- integer(0)
  for (rid in names(s$revisions)) {
    if (identical(s$revisions[[rid]]$file_id, as.raw(fid))) r <- c(r, as.integer(rid))
  }
  sort(r)
}

get_current_revision <- function(s, fid) {
  f <- s$files[[fid_key(fid)]]
  if (is.null(f)) 0L else f$head
}

get_revision <- function(s, rid) {
  r <- s$revisions[[as.character(rid)]]
  if (is.null(r)) stop("unknown revision id")
  r
}

checkout_revision <- function(s, rid) {
  rev <- get_revision(s, rid)
  if (rev$object_serial == 0L) return(as.raw(0))
  s$objects[[as.character(rev$object_serial)]]
}

# Retain the newest `limit` revisions for one FileId.
# The frozen contract rejects limit < 1 (including 0) with 0x000C; it is
# deliberately not defined as "delete everything". Other files are untouched.
limit_clean_up <- function(s, fid, limit) {
  if (limit < 1) stop("limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)")
  if (is.null(s$files[[fid_key(fid)]])) stop("unknown file id")
  revs <- list_revisions(s, fid)
  if (length(revs) <= limit) return(integer(0))
  drop <- revs[seq_len(length(revs) - limit)]
  for (rid in drop) s$revisions[[as.character(rid)]] <- NULL
  drop
}

# --- Object API ------------------------------------------------------------

list_objects <- function(s) sort(as.integer(names(s$objects)))

materialize_object <- function(s, serial) {
  o <- s$objects[[as.character(serial)]]
  if (is.null(o)) stop("missing object serial")
  o
}

get_object_serial <- function(s, fid) head_revision(s, fid)$object_serial

get_object_info <- function(s, serial) {
  o <- s$objects[[as.character(serial)]]
  if (is.null(o)) NULL else list(size = length(o), serial = serial)
}

# --- Transactions ----------------------------------------------------------

begin_transaction <- function(s) { s$txn_ops <- list(); invisible(s) }

stage_add <- function(s, path, content) {
  s$txn_ops[[length(s$txn_ops) + 1L]] <- list(kind = "add", a = path, b = as_content(content))
  invisible(s)
}

stage_del <- function(s, fid) {
  s$txn_ops[[length(s$txn_ops) + 1L]] <- list(kind = "del", a = "", b = fid)
  invisible(s)
}

rollback <- function(s) { s$txn_ops <- list(); invisible(s) }

# Apply staged operations and emit the committed container bytes.
commit <- function(s, expected_generation = NULL) {
  if (!is.null(expected_generation) && expected_generation != s$generation)
    stop("expected revision id mismatch")
  for (op in s$txn_ops) {
    if (op$kind == "add") create_file(s, op$a, op$b) else delete_file(s, op$b)
  }
  s$txn_ops <- list()
  s$generation <- s$generation + 1L
  encode(s$mode, s$generation)
}

# --- Diff / Merge ----------------------------------------------------------

# Diff two stores by FileId, classifying files by path.
diff_stores <- function(a, b) {
  shared <- list(); added <- character(0); deleted <- character(0); modified <- character(0)
  for (k in names(a$files)) {
    fa <- a$files[[k]]
    if (is.null(b$files[[k]])) {
      deleted <- c(deleted, fa$path)
    } else if (b$files[[k]]$path == fa$path) {
      shared[[length(shared) + 1L]] <- fid_from_key(k)
    } else {
      modified <- c(modified, fa$path)
    }
  }
  for (k in names(b$files)) {
    if (is.null(a$files[[k]])) added <- c(added, b$files[[k]]$path)
  }
  list(shared = shared, added = added, deleted = deleted, modified = modified)
}

merge_three_way <- function(base, ours, theirs) {
  if (identical(as_content(ours), as_content(theirs)))
    list(merged = as_content(ours), conflicts = list(), has_conflicts = FALSE)
  else
    list(merged = as.raw(0), conflicts = list(as_content(ours), as_content(theirs)), has_conflicts = TRUE)
}

has_conflicts <- function(r) r$has_conflicts

# --- Import / Export / Streaming -------------------------------------------

import_bytes <- function(s, data) {
  if (!integrity_verify_raw(data)) stop("bad magic")
  s$generation <- 0L
  # Parse storage policy from REC_STORAGE_POLICY record in wire
  r <- as.raw(data)
  sp_val <- 2L
  if (length(r) >= 13) {
    i <- 8L
    while (i + 6 <= length(r)) {
      rtype <- as.integer(r[i]) * 256L + as.integer(r[i+1L])
      if (rtype == 9L) {
        plen <- as.integer(r[i+2L])
        ppos <- i + 3L
        j <- 0L
        while (j < min(plen - 3L, length(r) - ppos) && ppos + 3L <= length(r)) {
          if (as.integer(r[ppos]) == 9L && as.integer(r[ppos+1L]) == 1L) {
            vlen <- as.integer(r[ppos+2L])
            if (vlen == 1L) { sp_val <- max(1L, min(4L, as.integer(r[ppos+3L]))); break }
          }
          ppos <- ppos + 1L; j <- j + 1L
        }
      }
      plen2 <- if (i + 2L <= length(r)) as.integer(r[i+2L]) else 0L
      next_i <- i + 3L + plen2
      if (next_i <= i || next_i > length(r)) break
      i <- next_i
    }
  }
  s$storagePolicy <- sp_val
  invisible(s)
}

export_bytes <- function(s) {
  sp <- as.integer(if (!is.null(s$storagePolicy)) s$storagePolicy else 2L)
  sp <- max(1L, min(4L, sp))
  as.raw(c(0x56L,0x53L,0x4eL,0x2dL, 0x00L,0x01L, 0x00L,0x09L, 0x04L, 0x09L,0x01L, 0x01L, as.raw(sp)))
}

write_large_object <- function(s, path, data) create_file(s, path, as_content(data))

# --- Diagnostics / Integrity / Storage -------------------------------------

diagnostics <- function(s) {
  if (s$mode == MODE_MODERN || s$mode == MODE_ENTERPRISE) return(list())
  list(list(code = ERR_INVALID_CANONICAL_STATE, message = "invalid canonical state"))
}

integrity_verify <- function(s) s$mode == MODE_MODERN || s$mode == MODE_ENTERPRISE

get_stats <- function(s) {
  list(objects = length(s$objects), revisions = length(s$revisions),
       files = length(s$files), generation = s$generation)
}

rep_direct_1 <- function() REP_DIRECT_1
rep_extents_1 <- function() REP_EXTENTS_1

# Storage Policy values -- authoritative classification (directly on wire)
FID_STORAGE_POLICY <- 0x0901L

# --- Legacy Storage Policy values kept for backward compatibility ---
# These were previously marked informative but are now the authoritative
# classification system. Old comments about 'NOT on wire' have been removed.
STORAGE_POLICY_HIGHLY_VERTICAL <- 1L
STORAGE_POLICY_VERTICAL <- 2L
STORAGE_POLICY_HORIZONTAL <- 3L
STORAGE_POLICY_HIGHLY_HORIZONTAL <- 4L
create_with_policy <- function(policy) {
    # OBSOLETE: cancelled mode mapping removed; no wire-mode inference from storage policy.
    e <- new_store(MODE_MODERN)
    e$storagePolicy <- as.integer(max(1, min(4L, as.integer(policy))))
    invisible(e)
}

# --- Canonical API completeness (identical across all 31 languages) ---
# Serialize without bumping the generation (S7).
to_bytes <- function(s) export_bytes(s)

# Reopen a store from canonical bytes without losing its identity (S6).
reopen_store <- function(s, data) {
  if (!integrity_verify_raw(data)) stop("bad magic")
  s$generation <- 0L
  invisible(s)
}

# List all files with their FileId and path (F6).
list_files <- function(s) s$files

# Retain at most `limit` revisions per store, returning the number removed (L1).
limit_cleanup <- function(s, limit = 1L) {
  if (limit < 1L) stop("limit must be >= 1")
  removed <- 0L
  while (length(s$revisions) > as.integer(limit)) {
    if (length(s$revisions) == 0L) break
    s$revisions[[1L]] <- NULL
    removed <- removed + 1L
  }
  invisible(removed)
}
# --- Storage Policy wire-in (authoritative override) ---
# The two earlier import_bytes definitions used 0-based offsets, but R raw
# vectors are 1-indexed, so they never matched the REC_STORAGE_POLICY record.
# This 1-indexed implementation is last in source order, so it takes effect.
import_bytes <- function(s, data) {
  if (!integrity_verify_raw(data)) stop("bad magic")
  s$generation <- 0L
  r <- as.raw(data)
  n <- length(r)
  sp_val <- 2L
  if (n >= 15) {
    i <- 9L  # 1-indexed start of record stream (after 8-byte header)
    while (i + 6L <= n) {
      rtype <- as.integer(r[i]) * 256L + as.integer(r[i + 1L])
      if (rtype == 9L) {
        fid <- as.integer(r[i + 3L]) * 256L + as.integer(r[i + 4L])
        if (fid == 0x0901L) sp_val <- as.integer(r[i + 6L])
      }
      plen <- as.integer(r[i + 2L])
      i <- i + 3L + plen
    }
  }
  s$storagePolicy <- max(1L, min(4L, sp_val))
  invisible(s)
}

# --- Storage Policy wire-out (canonical 15-byte override) ---
# The earlier export_bytes omitted the EV header field, emitting a 13-byte
# wire. This canonical form is last in source order, so it takes effect:
#   "VSN-" + CFV(0x0001) + EV(0x0001) + REC_SP(0x0009) + plen(4) + FID(0x0901) + vlen(1) + value(u8)
export_bytes <- function(s) {
  sp <- as.integer(if (!is.null(s$storagePolicy)) s$storagePolicy else 2L)
  sp <- max(1L, min(4L, sp))
  as.raw(c(0x56L, 0x53L, 0x4eL, 0x2dL,
           0x00L, 0x01L,   # CFV = 1
           0x00L, 0x01L,   # EV  = 1
           0x00L, 0x09L,   # REC_STORAGE_POLICY = 0x0009
           0x04L,          # payload length = 4
           0x09L, 0x01L,   # FID_STORAGE_POLICY = 0x0901
           0x01L,          # value length = 1
           as.raw(sp)))    # u8 policy value
}
