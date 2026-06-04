# soilinfiltration_config.R
# All configurable constants for the soil infiltration cleaning pipeline.
# Changing a threshold is a scientific decision — commit with a clear message.
#
# This pipeline mirrors scripts/clean_soilmoisture.R in structure and style.
# Season bounds are intentionally kept in sync with soilmoisture_config.R —
# both operate on the same 2026 Biosphere 2 campaign. If moisture changes
# SEASON_YEAR / SEASON_START / SEASON_END, update this file to match.

# ── External paths ─────────────────────────────────────────────────────────────
# DAILY_DATA_DIR: network drive folder containing daily entry .xlsx files.
#   Confirmed by Lindsey Bell 2026-06-04.
DAILY_DATA_DIR <- file.path("X:", "moore", "2026_B2_SoilProp", "Data",
                            "Infiltration",
                            "Soil_Infiltration_FieldData_Raw")

# MASTER_CSV: git-tracked master data file, relative to project root.
#   Parallel to data/B2_SoilMoisture_FullData.csv.
MASTER_CSV <- file.path("data", "B2_SoilInfiltration_FullData.csv")

# APPEND_LOG: run-level provenance log (outputs/ is gitignored; created at runtime).
#   Kept separate from outputs/append_log.csv (moisture) so both pipelines are
#   auditable independently.
APPEND_LOG <- file.path("outputs", "infiltration_append_log.csv")

# ── Season bounds (inclusive) ──────────────────────────────────────────────────
# First and last valid field days for the 2026 Biosphere 2 campaign.
# These match soilmoisture_config.R — same campaign, same measurement window.
# If moisture updates these, update here too.
SEASON_YEAR  <- 2026L
SEASON_START <- as.Date("2026-05-25")
SEASON_END   <- as.Date("2026-09-20")

# ── Allowed categorical values ─────────────────────────────────────────────────
# VALID_SUBPLOTS: sourced from soilmoisture_config.R rather than hardcoded so
#   the two pipelines cannot drift apart. The infiltration field sheet's
#   "Subplot" column uses the same location codes as the moisture "SoilType"
#   column (PSAM, THSL, TCAM, THCL, TCAL).
source("scripts/soilmoisture_config.R")
VALID_SUBPLOTS <- VALID_SOIL_TYPES   # rename locally; moisture constants stay in scope

# VALID_SOIL_TEXTURES: 12 USDA texture classes from data/reference/vg_parameters.csv.
#   Not hardcoded — the reference CSV is the single source of truth.
.vg <- read.csv(file.path("data", "reference", "vg_parameters.csv"),
                stringsAsFactors = FALSE)
VALID_SOIL_TEXTURES <- .vg$soil_type
rm(.vg)

# ── Instrument constants ───────────────────────────────────────────────────────
# INFILTROMETER_TYPE
#   Units:    categorical (must match a row in data/reference/infiltrometer_radii.csv)
#   Default:  "MiniDisk"
INFILTROMETER_TYPE <- "MiniDisk"

# RADIUS_CM
#   Units:    cm; valid: > 0
#   Loaded from data/reference/infiltrometer_radii.csv for INFILTROMETER_TYPE.
#   Disk radius enters I_t = (V0 - V_t) / (pi * r^2).
.radii <- read.csv(file.path("data", "reference", "infiltrometer_radii.csv"),
                   stringsAsFactors = FALSE)
RADIUS_CM <- .radii$radius_cm[.radii$infiltrometer_type == INFILTROMETER_TYPE][1]
if (!is.numeric(RADIUS_CM) || is.na(RADIUS_CM) || RADIUS_CM <= 0) {
  stop("INFILTROMETER_TYPE '", INFILTROMETER_TYPE,
       "' not found in infiltrometer_radii.csv or returned a non-positive radius.")
}
rm(.radii)

# ── Measurement constants ──────────────────────────────────────────────────────
# VALID_SUCTIONS_CM
#   Units:    cm (suction entered positive; h0 = -suction_cm)
#   Valid:    one of the eight discrete settings on the MiniDisk suction control
#   Rationale: the suction control has exactly these eight positions (METER spec);
#              any other value indicates a mis-entered setting
VALID_SUCTIONS_CM <- c(0.5, 1, 2, 3, 4, 5, 6, 7)

# MAX_VOLUME_ML
#   Units:    mL; valid: 0 <= Volume <= 95
#   Default:  95L
#   Rationale: Mini Disk reservoir capacity; values above this indicate a unit
#              error (e.g. cm³ entered) or a mid-run refill
MAX_VOLUME_ML <- 95L

# VOL_MONOTONIC_TOLERANCE_ML
#   Units:    mL; valid: >= 0
#   Default:  1
#   Rationale: reservoir volume should be non-increasing as water infiltrates;
#              a rise <= 1 mL is allowed for reading parallax (confirmed 2026-06-02)
VOL_MONOTONIC_TOLERANCE_ML <- 1

# TIME_MAX_S
#   Units:    seconds; valid: 0 <= Time <= 21600
#   Default:  3600L * 6L = 21600 (6 hours); confirmed by Lindsey Bell 2026-06-04
#   Rationale: the longest observed B2 run is ~3.5 h (12,815 s, TCAM subplot
#              on 2026-05-28); values above 21,600 s almost certainly indicate
#              minutes entered as seconds
TIME_MAX_S <- 3600L * 6L

# ── Curve-fit quality thresholds ───────────────────────────────────────────────
# MIN_FIT_POINTS
#   Units:    count; valid: >= 2
#   Default:  5L
#   Rationale: minimum points for a defensible I = C1*sqrt(t) + C2*t fit
#              (the fit has two free parameters); below this, K is UNKNOWN
MIN_FIT_POINTS <- 5L

# MIN_FIT_R2
#   Units:    dimensionless (0–1); valid: 0 <= r2 <= 1
#   Default:  0.95; ratified by Lindsey Bell 2026-06-04 for B2 soils
#   Rationale: below this, the replicate is flagged REVIEW_low_r2 (K is still
#              reported but the scientist reviews it); set to 0.95 rather than
#              the generic 0.90 because B2 soils produce consistently clean curves
MIN_FIT_R2 <- 0.95
