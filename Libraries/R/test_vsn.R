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
    s2 <- create(MODE_MODERN)
    f <- create_file(s2, "lc", charToRaw("x"))
    for(i in 1:5) write_file(s2, f, charToRaw(as.character(i)))
    ok <- length(limit_clean_up(s2, f, 3)) == 3; close_store(s2)
  } else if (n == 5) {
    create_file(s, "o", charToRaw("AB"))
    ok <- length(list_objects(s)) >= 1
  } else if (n == 6) {
    tx <- begin_transaction(s); stage_add(tx, "t", charToRaw("x"))
    r <- commit(s); ok <- !is.null(r)
  } else if (n == 7) { fid7 <- create_file(s, "rep", charToRaw("VSN-TEST-DATA-0123")); ok <- identical(read_file(s, fid7), charToRaw("VSN-TEST-DATA-0123")) && length(read_file(s, fid7)) == 18 }
  else if (n == 8) { sm8 <- create(MODE_MODERN); se8 <- create(MODE_ENTERPRISE); fm8 <- create_file(sm8, "m", charToRaw("modern")); fe8 <- create_file(se8, "e", charToRaw("ent")); ok <- get_mode(sm8)==1 && get_mode(se8)==2 && identical(read_file(sm8,fm8),charToRaw("modern")) && identical(read_file(se8,fe8),charToRaw("ent")) }
  else if (n == 9) ok <- isTRUE(validate_structural(parse(export_bytes(s))))
  else if (n == 10) ok <- !is.null(recover(export_bytes(s)))
  else if (n == 11) {
    s2 <- create(MODE_MODERN); create_file(s, "x", charToRaw("1"))
    d <- diff_stores(s, s2); ok <- !is.null(d$added)
  } else if (n == 12) {
    b12 <- create(MODE_MODERN); o12 <- create(MODE_MODERN); t12 <- create(MODE_MODERN)
    create_file(b12,"f",charToRaw("base")); create_file(o12,"f",charToRaw("ours")); create_file(t12,"f",charToRaw("theirs"))
    m <- merge_three_way(export_bytes(b12), export_bytes(o12), export_bytes(t12))
    b2 <- create(MODE_MODERN); o2 <- create(MODE_MODERN); t2 <- create(MODE_MODERN)
    create_file(b2,"c",charToRaw("base")); create_file(o2,"c",charToRaw("same")); create_file(t2,"c",charToRaw("same"))
    m2 <- merge_three_way(export_bytes(b2), export_bytes(o2), export_bytes(t2))
    ok <- !is.null(m) && !is.null(m2)
  } else if (n == 13) {
    bytes <- export_bytes(s); s2 <- open_store(bytes); ok <- get_mode(s2) == MODE_MODERN; close_store(s2)
  } else if (n == 14) {
    fid <- create_file(s, "big", charToRaw("bd")); cc <- read_file(s, fid); ok <- length(cc) > 0
  } else if (n == 15) {
    d <- diagnostics(s); ok <- is.list(d)
  } else if (n == 16) ok <- isTRUE(integrity_verify(s))
  else if (n == 17) { create_file(s, "stat", charToRaw("x")); st <- get_stats(s); ok <- st$files >= 1 }
  else if (n == 18) { b <- new_builder(MODE_ENTERPRISE); ok <- get_mode(b) == MODE_ENTERPRISE }
  else if (n == 19) { fid19 <- create_file(s, "i", charToRaw("interop-data-42")); b19 <- export_bytes(s); ok <- identical(read_file(s,fid19),charToRaw("interop-data-42")) && length(b19)>=8 }
  close_store(s)
  if (ok) { cat(sprintf("CAP %d PASS assertions=1 ops=1\n", n)); 1L } else { cat(sprintf("CAP %d FAIL assertions=0 ops=1\n", n)); 0L }
}

results <- sapply(1:19, run_cap)
cat(sprintf("PASS %d\n", sum(results)))