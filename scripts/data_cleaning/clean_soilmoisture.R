# clean_soilmoisture.R
# Run from RStudio with SoilProperties.Rproj open (working dir = project root).
# Open the project, then call: source("scripts/data_cleaning/clean_soilmoisture.R")
# Stops loudly at the first failing step; fix the source file and re-run.

if (!interactive()) {
  stop(
    "This script must be run interactively from RStudio ",
    "(source it, don't Rscript it)."
  )
}

source("scripts/functions_config/soilmoisture_config.R")
source("scripts/functions_config/soilmoisture_cleaning_functions.R")

library(openxlsx)
library(dplyr)

# ── Get filename ────────────────────────────────────────────────────────
filename <- trimws(readline(
  "Enter daily entry filename (e.g. B2_SoilMoisture_20260601.xlsx): "
))
if (nchar(filename) == 0) {
  stop("No filename entered. Re-run and provide a filename.")
}

filepath <- file.path(DAILY_DATA_DIR, filename)

# ── Parse date from filename ────────────────────────────────────────────
date         <- parse_date_from_filename(filename)
date_compact <- format(date, "%Y%m%d")
date_str     <- format(date, "%Y-%m-%d")
message("\nProcessing: ", filename, "  (date: ", date_str, ")")

# ── Step 1: Compare double entries ──────────────────────────────────────
message("\n── Step 1: Comparing Sheet1 and Sheet2 ────────────────────────")
sheets <- read_entry_sheets(filepath)
compare_sheets(sheets$sheet1, sheets$sheet2)
message(
  "Step 1 passed: Sheet1 and Sheet2 agree on all ",
  nrow(sheets$sheet1), " row(s)."
)

# ── Step 2: Validate date; interactively review row violations ───────────
message("\n── Step 2: Validating data ─────────────────────────────────────")
validate_rows(sheets$sheet1, date)   # date only — stops loudly on date violation

viols <- detect_row_violations(sheets$sheet1)
if (nrow(viols) == 0) {
  sheets$sheet1$Flag <- NA_character_
  message("Step 2 passed: all ", nrow(sheets$sheet1), " row(s) are valid.")
} else {
  sheets$sheet1 <- review_violations(sheets$sheet1, viols, filepath)
  # Final re-check: only unflagged rows need to be clean
  flagged_rows <- which(!is.na(sheets$sheet1$Flag) & sheets$sheet1$Flag == "REVIEW")
  final_viols  <- detect_row_violations(sheets$sheet1)
  remaining    <- final_viols[!final_viols$row %in% flagged_rows, , drop = FALSE]
  if (nrow(remaining) > 0) {
    message("Final re-check: ", nrow(remaining), " unresolved violation(s):")
    print(remaining, row.names = FALSE)
    stop("Unresolved violations after review. Fix the source .xlsx and re-run.")
  }
  n_flagged <- length(flagged_rows)
  message(
    "Step 2 complete: ", n_flagged, " row(s) flagged REVIEW, ",
    nrow(sheets$sheet1) - n_flagged, " row(s) clean."
  )
}

# ── Step 3: Append to master CSV ────────────────────────────────────────
message("\n── Step 3: Appending to master CSV ────────────────────────────")
do_replace <- check_duplicate_date(MASTER_CSV, date)
appended   <- append_to_master(
  sheets$sheet1, date, MASTER_CSV, replace = do_replace
)
write_append_log(APPEND_LOG, filename, nrow(appended), date)
message(
  "Appended ", nrow(appended), " rows for ", format(date),
  " to ", MASTER_CSV, "."
)

# ── Step 4: Git workflow ─────────────────────────────────────────────────────
cat(paste0(
  "\n── Next steps: commit and open a pull request ───────────────────\n",
  "Run these commands in your terminal:\n\n",
  "  git checkout -b data/soilmoisture/", date_compact, "\n",
  "  git add data/B2_SoilMoisture_FullData.csv\n",
  "  git commit -m \"[data] add soil moisture ", date_str, "\"\n",
  "  git push -u origin data/soilmoisture/", date_compact, "\n\n",
  "Open a pull request on GitHub for Lindsey to review before merging.\n"
))
