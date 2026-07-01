# summarise_soilmoisture.R
# Run from RStudio with SoilProperties.Rproj open (working dir = project root).
# Call: source("scripts/data_cleaning/summarise_soilmoisture.R")
#
# Reads data/Full/B2_SoilMoisture_FullData.csv, groups by Date + SoilType + PlantID,
# and summarises each Sensor/Depth combination to mean and SD across readings.
# Writes wide-format output to data/processed/B2_SoilMoisture_Summary.csv.

if (!interactive()) {
  stop(
    "This script must be run interactively from RStudio ",
    "(source it, don't Rscript it)."
  )
}

source("scripts/functions_config/soilmoisture_config.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

# ── Read master CSV ────────────────────────────────────────────────────────────

moisture_full <- read.csv(
  file.path("data", "Full", "B2_SoilMoisture_FullData.csv"),
  colClasses = c(PlantID = "character"),
  stringsAsFactors = FALSE
)

if (nrow(moisture_full) == 0) {
  stop("B2_SoilMoisture_FullData.csv is empty — nothing to summarise.")
}

# ── Summarise: mean and SD per Date + SoilType + PlantID + Sensor + Depth ────

summary_long <- moisture_full |>
  dplyr::mutate(Date = as.Date(Date)) |>
  dplyr::group_by(Date, SoilType, PlantID, Sensor, Depth) |>
  dplyr::summarise(
    mean = mean(Value, na.rm = TRUE),
    sd   = sd(Value,   na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(sensor_depth = paste0(Sensor, "_", Depth))

# ── Pivot to wide: one column per {Sensor}_{Depth}_mean / _sd ─────────────────

summary_wide <- summary_long |>
  tidyr::pivot_wider(
    id_cols     = c(Date, SoilType, PlantID),
    names_from  = sensor_depth,
    values_from = c(mean, sd),
    names_glue  = "{sensor_depth}_{.value}"
  ) |>
  dplyr::arrange(Date, SoilType, PlantID)

# ── Write output ──────────────────────────────────────────────────────────────

out_path <- file.path("data", "processed", "B2_SoilMoisture_Summary.csv")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write.csv(summary_wide, out_path, row.names = FALSE)

message(
  "Wrote ", nrow(summary_wide), " rows to ", out_path, ".\n",
  "Columns: ", paste(names(summary_wide), collapse = ", ")
)
