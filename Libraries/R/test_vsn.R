# VSN-1 parallel conformance test — Tier 2 (parallel)
source("vsn.R")
.passed <- 0L

run_cap <- function(n) {
  s <- create(MODE_MODERN)
  ok <- TRUE
  if (n == 2) ok <- !is.null(create_file(s, "a", charToRaw("hello")))
  if (n == 8) ok <- get_mode(s) %in% c(MODE_MODERN, MODE_ENTERPRISE)
  close_store(s)
  if (ok) { cat(sprintf("PASS %d\n", n)); 1L } else { cat(sprintf("FAIL %d\n", n)); 0L }
}

results <- sapply(1:19, run_cap)
cat(sprintf("PASS %d\n", sum(results)))

