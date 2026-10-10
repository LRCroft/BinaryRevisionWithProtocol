# VSN-1 independent consumer (R) -- Storage Policy round-trip.
# Uses the library's create_with_policy + export_bytes (wire-out)
# + open_store (wire-in).
source("../../R/vsn.R")

sig <- function(b) {
  n <- length(b); hi <- if (n > 7) n - 7 else 0
  for (i in 0:hi) {
    if (b[i + 1] == 0 && b[i + 2] == 9 && b[i + 3] == 4 &&
        b[i + 4] == 9 && b[i + 5] == 1 && b[i + 6] == 1) return(TRUE)
  }
  FALSE
}

bad <- FALSE
for (p in 1:4) {
  s  <- create_with_policy(p)
  b  <- export_bytes(s)
  if (!isTRUE(sig(b))) { cat(sprintf("FAIL p=%d wire-out\n", p)); bad <- TRUE }
  s2 <- import_bytes(create(1), b)
  got <- if (!is.null(s2) && !is.null(s2$storagePolicy)) s2$storagePolicy else NULL
  if (is.null(got) || as.integer(got) != as.integer(p)) {
    cat(sprintf("FAIL p=%d got=%s\n", p, if (is.null(got)) "NULL" else as.character(got)))
    bad <- TRUE
  }
}
cat(if (bad) "CONSUMER R FAIL\n" else "CONSUMER R PASS\n")
if (bad) quit(status = 1, save = "no")
