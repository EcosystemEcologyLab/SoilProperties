# clean_soilmoisture.R
# Run from RStudio with SoilProperties.Rproj open (working dir = project root).
# Open the project, then call: source("scripts/clean_soilmoisture.R")
# Stops loudly at the first failing step; fix the source file and re-run.

if (!interactive()) {
  stop(
    "This script must be run interactively from RStudio ",
    "(source it, don't Rscript it)."
  )
}

source("scripts/soilmoisture_config.R")
source("scripts/soilmoisture_cleaning_functions.R")

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
date <- parse_date_from_filename(filename)
message("\nProcessing: ", filename, "  (date: ", format(date), ")")

# ── Step 1: Compare double entries ──────────────────────────────────────
message("\n── Step 1: Comparing Sheet1 and Sheet2 ────────────────────────")
sheets <- read_entry_sheets(filepath)
compare_sheets(sheets$sheet1, sheets$sheet2)
message(
  "Step 1 passed: Sheet1 and Sheet2 agree on all ",
  nrow(sheets$sheet1), " row(s)."
)

# ── Step 2: Validate ranges and codes ───────────────────────────────────
message("\n── Step 2: Validating data ranges and codes ────────────────────")
validate_rows(sheets$sheet1, date)
message("Step 2 passed: all ", nrow(sheets$sheet1), " row(s) are valid.")

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
message("\n── Next steps: commit and open a pull request ───────────────────")
message("Run these commands in a terminal:\n")
message("  git checkout -b data/soilmoisture/", date_compact)
message("  git add data/B2_SoilMoisture_FullData.csv")
message("  git commit -m \"[data] add soil moisture ", date_str, "\"")
message("  git push -u origin data/soilmoisture/", date_compact)
message("\nOpen a pull request on GitHub for Lindsey to review before merging.")
