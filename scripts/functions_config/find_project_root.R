# Walk up from `start` until CLAUDE.md is found; return that directory path.
.find_project_root <- function(start = getwd()) {
  d <- normalizePath(start, winslash = "/")
  while (!file.exists(file.path(d, "CLAUDE.md"))) {
    parent <- dirname(d)
    if (parent == d) stop("Could not find project root (no CLAUDE.md found above ", start, ")")
    d <- parent
  }
  d
}
