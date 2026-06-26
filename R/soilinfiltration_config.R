# soilinfiltration_config.R
# All configurable constants for the soil infiltration pipeline.
# Changing a threshold is a scientific decision — commit with a clear message.

# ── Input paths ────────────────────────────────────────────────────────────────
# DAILY_DATA_DIR: network drive folder containing daily entry .xlsx files.
# Confirmed by Lindsey Bell 2026-06-04.
# The drive letter is read from the INFILTRATION_DATA_DRIVE environment
# variable (set in a local .env file — see .env.example). Defaults to X:
# if not set. Each team member sets their own drive letter locally;
# .env is gitignored and never committed.
.drive <- Sys.getenv("INFILTRATION_DATA_DRIVE", unset = "X:")
DAILY_DATA_DIR <- file.path(.drive, "moore", "2026_B2_SoilProp", "Data",
                            "Infiltration", "Soil_Infiltration_FieldData_Raw")
rm(.drive)

# ── Output paths ───────────────────────────────────────────────────────────────
# MASTER_CSV: git-tracked master data file, relative to project root.
MASTER_CSV <- file.path("data", "B2_SoilInfiltration_FullData.csv")

# APPEND_LOG: run-level provenance log (outputs/ is gitignored; created at runtime).
APPEND_LOG <- file.path("outputs", "infiltration_append_log.csv")

# ── Season bounds (inclusive) ──────────────────────────────────────────────────
# First and last valid field days for the 2026 Biosphere 2 campaign.
SEASON_YEAR  <- 2026L
SEASON_START <- as.Date("2026-05-25")
SEASON_END   <- as.Date("2026-09-20")

# ── Allowed categorical values ─────────────────────────────────────────────────
# VALID_SOIL_TYPES: field abbreviations used in the SoilType column of the daily
# entry .xlsx files. These map to USDA texture classes via
# data/reference/subplot_soiltexture.csv.
VALID_SOIL_TYPES <- c("PSAM", "THSL", "TCAM", "THCL", "TCAL")

# ── Instrument constants ───────────────────────────────────────────────────────
# INFILTROMETER_TYPE: matches a row in data/reference/infiltrometer_radii.csv.
INFILTROMETER_TYPE <- "MiniDisk"

# RADIUS_CM: disk radius (cm); from data/reference/infiltrometer_radii.csv.
# Enters I_t = (V0 - V_t) / (pi * r^2) and the Zhang (1997) A coefficient.
RADIUS_CM <- 2.25

# ── Measurement constants ──────────────────────────────────────────────────────
# VALID_SUCTIONS_CM
#   Units:    cm (suction entered positive; h0 = -suction_cm in calculations)
#   Valid:    the eight discrete positions on the MiniDisk suction control (METER spec)
#   Rationale: any other value indicates a mis-entered setting
VALID_SUCTIONS_CM <- c(0.5, 1, 2, 3, 4, 5, 6, 7)

# MAX_VOLUME_ML
#   Units:    mL; MiniDisk reservoir capacity
#   Rationale: values above this indicate a unit error or a mid-run refill
MAX_VOLUME_ML <- 95

# VOL_MONOTONIC_TOLERANCE_ML
#   Units:    mL; reservoir volume should be non-increasing as water infiltrates
#   Rationale: a rise <= 1 mL is allowed for reading parallax (confirmed 2026-06-02)
VOL_MONOTONIC_TOLERANCE_ML <- 1

# TIME_MAX_S
#   Units:    seconds; valid: 0 <= Time <= 21600 (6 hours)
#   Rationale: values above 21 600 s almost certainly indicate minutes entered as seconds
#   Confirmed by Lindsey Bell 2026-06-04
TIME_MAX_S <- 3600L * 6L

# ── Curve-fit quality thresholds ───────────────────────────────────────────────
# MIN_FIT_POINTS
#   Units:    count; valid: >= 2
#   Default:  5L; below this, the fit has too few degrees of freedom to be reliable
MIN_FIT_POINTS <- 5L

# MIN_FIT_R2
#   Units:    dimensionless (0–1)
#   Default:  0.95; below this the replicate is flagged REVIEW_low_r2
#   Ratified by Lindsey Bell 2026-06-04 for B2 soils
MIN_FIT_R2 <- 0.95

# ── Per-texture K upper bounds (soft QC thresholds) ────────────────────────────
# K_UPPER_CM_HR: soft upper bounds for saturated hydraulic conductivity per USDA
# texture class, in cm/hr. Source: METER MiniDisk manual Table 2 and standard
# soil hydraulic literature (Rawls et al.; Carsel & Parrish 1988).
# These are NOT hard validity cutoffs — a K above the bound triggers
# REVIEW_high_K so the scientist can check field notes, but K is still reported.
K_UPPER_CM_HR <- c(
  "Sand"             = 500,
  "Loamy Sand"       = 150,
  "Sandy Loam"       = 50,
  "Loam"             = 6,
  "Silt"             = 6,
  "Silt Loam"        = 6,
  "Sandy Clay Loam"  = 4,
  "Clay Loam"        = 3,
  "Silty Clay Loam"  = 2,
  "Sandy Clay"       = 2,
  "Silty Clay"       = 1,
  "Clay"             = 1
)
