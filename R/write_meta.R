# =============================================================================
# write_meta.R — provenance metadata companion writer
# -----------------------------------------------------------------------------
# Implements the output-metadata requirement of SCIENCE_PRINCIPLES_PIPELINES.md.
# Every CSV / figure produced by scripts 02 and 03 gets a "{filename}.meta.json"
# companion with: run_datetime_utc, pipeline_version, input_sources (paths +
# SHA256), r_session_info (path), notes.
#
# Sourced by R/02_calculate_infiltration.R and R/03_append_fulldata.R.
# Depends on: jsonlite, digest (both in the locked dependency set).
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
})

#' Current UTC time as an ISO 8601 string (e.g. "2026-06-02T18:25:56Z").
#' @return Character scalar.
.utc_now_iso <- function() {
  format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
}

#' Short git commit hash of the repository at run time.
#'
#' Captured programmatically per SCIENCE_PRINCIPLES_PIPELINES.md. Returns
#' "UNKNOWN_no_git" rather than failing if git is unavailable, so that metadata
#' is always written (a missing field is worse than a flagged-unknown one).
#' @return Character scalar.
pipeline_version <- function() {
  hash <- tryCatch(
    suppressWarnings(system("git rev-parse --short HEAD", intern = TRUE,
                            ignore.stderr = TRUE)),
    error = function(e) character(0))
  if (length(hash) == 0 || !nzchar(hash[1])) "UNKNOWN_no_git" else hash[1]
}

#' Write outputs/session_info.txt (the canonical r_session_info target).
#'
#' Gitignored but must be present with every output set.
#' @param path Destination path (default PATH_SESSION_INFO from config).
#' @return Invisibly the path written.
write_session_info <- function(path = PATH_SESSION_INFO) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  writeLines(capture.output(sessionInfo()), path)
  invisible(path)
}

#' Build the input_sources list: each input path plus its SHA256 hash.
#'
#' @param paths Character vector of input file paths.
#' @return List of {path, sha256} entries (sha256 = "FILE_NOT_FOUND" if absent).
.input_sources <- function(paths) {
  lapply(paths, function(p) {
    sha <- if (file.exists(p)) digest::digest(file = p, algo = "sha256") else "FILE_NOT_FOUND"
    list(path = p, sha256 = sha)
  })
}

#' Write a {target}.meta.json companion file.
#'
#' @param target_path Path of the output file the metadata describes.
#' @param input_sources Character vector of input file paths (hashed).
#' @param notes Free-text notes (required; empty string acceptable, NULL not).
#' @param session_info_path Path to the saved sessionInfo() file.
#' @param extra Optional named list of additional fields to merge in.
#' @return Invisibly the path of the metadata file written.
write_meta <- function(target_path,
                       input_sources,
                       notes,
                       session_info_path = PATH_SESSION_INFO,
                       extra = list()) {
  if (is.null(notes)) {
    stop("write_meta(): 'notes' is required (empty string OK, NULL not). ",
         "See SCIENCE_PRINCIPLES_PIPELINES.md output-metadata rules.")
  }
  meta <- c(list(
    run_datetime_utc = .utc_now_iso(),
    pipeline_version = pipeline_version(),
    input_sources    = .input_sources(input_sources),
    r_session_info   = session_info_path,
    notes            = notes
  ), extra)

  meta_path <- paste0(target_path, ".meta.json")
  dir.create(dirname(meta_path), showWarnings = FALSE, recursive = TRUE)
  write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  invisible(meta_path)
}
