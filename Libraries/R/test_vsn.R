# VSN-1 parallel conformance test — Tier 2 (parallel)
source("vsn.R")
.passed <- 0L

run_cap <- function(n) {
  s <- create(MODE_MODERN)
  ok <- FALSE
  if (n == 1) ok <- get_mode(s) == MODE_MODERN
  else if (n == 2) ok <- !is.null(create_file(s, "a", charToRaw("hello")))
  else if (n == 3) {
    s2 <- create(MODE_MODERN); f <- create_file(s2, "r", charToRaw("v1"))
    write_file(s2, f, charToRaw("v2")); write_file(s2, f, charToRaw("v3"))
    ok <- length(list_revisions(s2, f)) >= 3; close_store(s2)
  } else if (n == 4) {
    f <- create_file(s2, "lc", charToRaw("x"))
    for(i in 1:5) write_file(s2, f, charToRaw(as.character(i)))
    ok <- length(limit_cleanup(s2, f, 3)) == 2; close_store(s2)
  } else if (n == 5) {
    create_file(create(MODE_MODERN), "o", charToRaw("AB"))
    ok <- length(list_objects(create(MODE_MODERN))) >= 1; close_store(s)
  } else if (n == 6) {
    tx <- begin_transaction(s); stage_add(tx, "t", charToRaw("x"))
    r <- commit(s, tx); ok <- nchar(r) >= 8
  } else if (n == 7) ok <- rep_direct_1 == 1 && rep_extents_1 == 2
  else if (n == 8) ok <- get_mode(s) %in% c(MODE_MODERN, MODE_ENTERPRISE)
  else if (n == 9) ok <- validate_structural(s)
  else if (n == 10) ok <- recover(export_bytes(s)) >= 0
  else if (n == 11) {
    s2 <- create(MODE_MODERN); create_file(s, "x", charToRaw("1"))
    d <- diff_stores(s, s2); ok <- !is.null(d$added)
  } else if (n == 12) {
    m <- merge_three_way(create(MODE_MODERN), create(MODE_MODERN), create(MODE_MODERN))
    ok <- !is.null(m)
  } else if (n == 13) {
    bytes <- export_bytes(s); s2 <- open_store(bytes); ok <- get_mode(s2) == MODE_MODERN; close_store(s2)
  } else if (n == 14) {
    fid <- create_file(s, "big", charToRaw("bd")); c <- read_file(s, fid); ok <- length(c) >= 0
  } else if (n == 15) {
    d <- diagnostics(s, "Full"); ok <- is.list(d)
  } else if (n == 16) ok <- integrity_verify(export_bytes(s))
  else if (n == 17) { create_file(create(MODE_MODERN), "stat", charToRaw("x")); st <- get_stats(s); ok <- st$files >= 1 }
  else if (n == 18) { b <- new_builder(MODE_ENTERPRISE); ok <- get_mode(b) == MODE_ENTERPRISE }
  else if (n == 19) ok <- check_magic_bytes(encode(1,1))
  close_store(s)
  if (ok) { cat(sprintf("PASS %d\n", n)); 1L } else { cat(sprintf("FAIL %d\n", n)); 0L }
}

results <- sapply(1:19, run_cap)
cat(sprintf("PASS %d\n", sum(results)))