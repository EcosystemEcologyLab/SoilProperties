# Root all tests at the project directory so the pipeline's relative paths
# (data/reference/..., outputs/..., R/...) resolve correctly.

.find_root <- function(start = getwd()) {
  d <- normalizePath(start, winslash = "/")
  while (!file.exists(file.path(d, "CLAUDE.md"))) {
    parent <- dirname(d)
    if (parent == d) stop("Could not find project root (no CLAUDE.md found above ", start, ")")
    d <- parent
  }
  d
}

PROJECT_ROOT <- .find_root()
setwd(PROJECT_ROOT)

# Shared math + config (sourced once; individual tests source scripts as needed).
source(file.path(PROJECT_ROOT, "R", "infiltration_math.R"))
