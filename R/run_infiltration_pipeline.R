# run_infiltration_pipeline.R
# One-stop runner for a new field day of soil infiltration data.
# Run from RStudio with SoilProperties.Rproj open (working dir = project root).
# Call: source("R/run_infiltration_pipeline.R")
#
# Inputs:
#   - A daily entry .xlsx (Soil_Infiltration_FieldData_YYYYMMDD.xlsx) in data/raw/
#   - The existing master CSV (data/B2_SoilInfiltration_FullData.csv)
#   - Reference tables in data/reference/
#
# Outputs (on success):
#   - data/B2_SoilInfiltration_FullData.csv        updated master (git-tracked)
#   - data/processed/B2_SoilInfiltration_Results.csv  K per replicate
#   - figures/B2_SoilInfiltration_curves_<YYYYMMDD>.png
#   - outputs/infiltration_append_log.csv           provenance log (gitignored)
#
# Stops loudly at any validation failure. Fix the source .xlsx and re-run.

if (!interactive()) {
  stop(
    "This script must be run interactively from RStudio ",
    "(source it, don't Rscript it)."
  )
}

source("R/soilinfiltration_config.R")
source("R/soilinfiltration_cleaning_functions.R")

library(openxlsx)

# ── Get file path ─────────────────────────────────────────────────────────────
path_input <- trimws(readline(paste0(
  "Enter .xlsx path (relative to project root, absolute, or bare filename",
  " to look in data/raw/): "
)))
if (nchar(path_input) == 0) {
  stop("No path entered. Re-run and provide a path.")
}

# Bare filename (no directory separator) → default to data/raw/
filepath <- if (grepl("[/\\\\]", path_input) || file.exists(path_input)) {
  path_input
} else {
  file.path("data", "raw", path_input)
}

message("Resolved path: ", normalizePath(filepath, mustWork = FALSE))

# ── Parse date from filename ──────────────────────────────────────────────────
date         <- parse_date_from_filename(filepath)
date_str     <- format(date, "%Y-%m-%d")
date_compact <- format(date, "%Y%m%d")
message("\nProcessing: ", basename(filepath), "  (date: ", date_str, ")")

# ── Step 1: Compare double entries ────────────────────────────────────────────
message("\n── Step 1: Comparing Sheet1 and Sheet2 ─────────────────────────")
sheets <- read_entry_sheets(filepath)
compare_sheets(sheets$sheet1, sheets$sheet2)
message(
  "Step 1 passed: Sheet1 and Sheet2 agree on all ",
  nrow(sheets$sheet1), " row(s)."
)

# ── Step 2: Validate ranges and codes ────────────────────────────────────────
message("\n── Step 2: Validating data ranges and codes ─────────────────────")
validate_rows(sheets$sheet1, date)
message("Step 2 passed: all ", nrow(sheets$sheet1), " row(s) are valid.")

# ── Step 3: Append to master CSV ─────────────────────────────────────────────
message("\n── Step 3: Appending to master CSV ─────────────────────────────")
do_replace <- check_duplicate_date(MASTER_CSV, date)
appended   <- append_to_master(
  sheets$sheet1, date, filepath, MASTER_CSV, replace = do_replace
)
write_append_log(APPEND_LOG, filepath, nrow(appended), date)
message(
  "Appended ", nrow(appended), " rows for ", date_str,
  " to ", MASTER_CSV, "."
)

# ── Step 4: Compute K ────────────────────────────────────────────────────────
message("\n── Step 4: Computing K (fitting infiltration curves) ────────────")
source("R/calculate_infiltration.R")
run_calculate_infiltration()

# ── Git workflow ──────────────────────────────────────────────────────────────
message("\n── Next steps: commit and open a pull request ───────────────────")
message("Run these commands in a terminal:\n")
message("  git checkout -b data/infiltration/", date_compact)
message("  git add data/B2_SoilInfiltration_FullData.csv data/processed/B2_SoilInfiltration_Results.csv")
message("  git commit -m \"[data] add infiltration ", date_str, "\"")
message("  git push -u origin data/infiltration/", date_compact)
message("\nOpen a pull request on GitHub for Lindsey to review before merging.")
