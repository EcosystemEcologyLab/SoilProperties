# =============================================================================
# 03_append_fulldata.R — append replicate results to the long-format FullData
# -----------------------------------------------------------------------------
# Usage:  Rscript R/03_append_fulldata.R <path/to/{...}_infiltration_results.csv>
#
# Appends results rows to data/processed/B2_SoilInfiltration_FullData.xlsx
# (created if absent), in long format. Dedup key: (site, date, plot, point_id).
#
# Never silently overwrites (SCIENCE_PRINCIPLES.md, human authority):
#   * If an incoming key already exists in FullData, it is PRESERVED and the
#     collision is logged to the unknown log with reason
#     "duplicate_key_existing_preserved".
#   * To deliberately replace an existing record, the scientist adds a row to
#     data/overrides/infiltration_overrides.csv (decision = "replace"). The
#     pipeline reads override files but never writes to them.
# =============================================================================

source("R/pipeline_config.R")
source("R/write_meta.R")

suppressPackageStartupMessages({
  library(openxlsx)
  library(dplyr)
})

THIS_SCRIPT <- "03_append_fulldata.R"
PATH_OVERRIDE_FILE <- file.path(PATH_OVERRIDES, "infiltration_overrides.csv")

.key <- function(df) paste(df$site, df$date, df$plot, df$point_id, sep = "_")

#' Read replace-decisions from the human override file (never modified here).
#' @return character vector of record_ids approved for replacement.
.read_replace_overrides <- function() {
  if (!file.exists(PATH_OVERRIDE_FILE)) return(character(0))
  ov <- read.csv(PATH_OVERRIDE_FILE, stringsAsFactors = FALSE)
  needed <- c("record_id", "decision")
  if (!all(needed %in% names(ov))) {
    stop("Override file ", PATH_OVERRIDE_FILE, " missing columns: ",
         paste(setdiff(needed, names(ov)), collapse = ", "))
  }
  ov$record_id[tolower(trimws(ov$decision)) == "replace"]
}

#' Main driver.
#' @param results_csv Path to a results CSV from script 02.
run_append_fulldata <- function(results_csv) {
  check_pipeline_config()
  ensure_logs_exist()
  write_session_info()

  if (!file.exists(results_csv)) stop("Results CSV not found: ", results_csv)
  incoming <- read.csv(results_csv, stringsAsFactors = FALSE,
                       colClasses = c(date = "character"))
  if (nrow(incoming) == 0) stop("Results CSV has no rows: ", results_csv)
  incoming$.key <- .key(incoming)

  replace_ids <- .read_replace_overrides()
  applied_overrides <- character(0)

  dir.create(PATH_PROCESSED, showWarnings = FALSE, recursive = TRUE)

  if (file.exists(PATH_FULLDATA)) {
    existing <- openxlsx::read.xlsx(PATH_FULLDATA, sheet = 1)
    existing$date <- as.character(existing$date)
    existing$.key <- .key(existing)
  } else {
    existing <- incoming[0, , drop = FALSE]
  }

  n_appended <- 0L; n_replaced <- 0L
  collisions <- list()

  for (i in seq_len(nrow(incoming))) {
    row <- incoming[i, , drop = FALSE]
    k <- row$.key
    if (!(k %in% existing$.key)) {
      existing <- dplyr::bind_rows(existing, row)        # new key -> append
      n_appended <- n_appended + 1L
    } else if (k %in% replace_ids) {
      existing <- existing[existing$.key != k, , drop = FALSE]
      existing <- dplyr::bind_rows(existing, row)        # override -> replace
      applied_overrides <- c(applied_overrides, k)
      n_replaced <- n_replaced + 1L
    } else {
      collisions[[length(collisions) + 1]] <- data.frame(  # preserve existing
        record_id = k,
        reason = "duplicate_key_existing_preserved",
        logged_by = THIS_SCRIPT, stringsAsFactors = FALSE)
    }
  }

  if (length(collisions)) log_unknowns(dplyr::bind_rows(collisions))

  out <- existing %>%
    select(-.key) %>%
    arrange(site, date, plot, point_id)
  openxlsx::write.xlsx(out, PATH_FULLDATA, overwrite = TRUE)

  ov_note <- if (length(applied_overrides))
    paste0("override replace applied to: ", paste(applied_overrides, collapse = "; "))
  else "no overrides applied"
  write_meta(PATH_FULLDATA,
             input_sources = c(results_csv, PATH_OVERRIDE_FILE),
             notes = sprintf("appended=%d, replaced=%d, collisions_preserved=%d; %s",
                             n_appended, n_replaced, length(collisions), ov_note))

  message(sprintf(
    "Script 03 complete: %d records read, %d appended, %d replaced (override), %d collisions preserved (unknown log)",
    nrow(incoming), n_appended, n_replaced, length(collisions)))
  message("  -> ", PATH_FULLDATA)

  invisible(PATH_FULLDATA)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript R/03_append_fulldata.R <results_csv>")
  }
  run_append_fulldata(args[1])
}
