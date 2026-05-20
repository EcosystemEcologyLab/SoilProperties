# soilmoisture_config.R
# All configurable constants for the soil moisture cleaning pipeline.
# Changing a threshold is a scientific decision — commit with a clear message.

# ── External paths ─────────────────────────────────────────────────────────────
# DAILY_DATA_DIR: network drive folder containing daily entry .xlsx files.
#   Change the drive letter / path if the mapping differs on your machine.
DAILY_DATA_DIR <- file.path("X:", "moore", "2026_B2_SoilProp", "Data",
                            "SoilMoisture", "B2_SoilMoisture_DataSheet_DailyData")

# MASTER_CSV: git-tracked master data file, relative to project root.
MASTER_CSV  <- file.path("X:", "moore", "2026_B2_SoilProp",
                         "Code", "data", "B2_SoilMoisture_FullData.csv")

# APPEND_LOG: run-level provenance log (outputs/ is gitignored; created at runtime).
APPEND_LOG  <- file.path("outputs", "append_log.csv")

# ── Season bounds (inclusive) ──────────────────────────────────────────────────
# First and last valid field days for the 2026 Biosphere 2 campaign.
SEASON_YEAR  <- 2026L
SEASON_START <- as.Date("2026-05-25")
SEASON_END   <- as.Date("2026-09-20")

# ── Allowed categorical values ─────────────────────────────────────────────────
VALID_SOIL_TYPES <- c("PSAM", "THSL", "TCAM", "THCL", "TCAL")

VALID_SENSORS <- c("T", "M")

VALID_SPECIES_CODES <- c(
  "RhuOva", "IndSuf", "HetArb", "RueCal", "SalApi",
  "GosDav", "BurHin", "LycBre", "BacSal", "AcaNot",
  "EupMil", "DonVis", "TecSta", "HypEmo", "CyrEdu",
  "MayPhy", "FouDig", "ParArg", "MexOrc", "UnkVeg"
)

# ── Depth rules (cm) ───────────────────────────────────────────────────────────
# Moisture sensors (M) are installed at fixed depths; any other depth is a typo.
DEPTH_M_VALID <- c(12L, 20L)

# Temperature sensors (T) can be placed at any depth from 1 to 80 cm.
DEPTH_T_MIN <- 1L    # exclusive zero: depth must be > 0
DEPTH_T_MAX <- 80L

# ── Value ranges ───────────────────────────────────────────────────────────────
# Moisture sensor (M): volumetric water content (% VWC). Values outside 0–40
# indicate sensor failure or a data entry error.
VALUE_M_MIN <- 0
VALUE_M_MAX <- 40

# Temperature sensor (T): degrees Celsius. Values outside 10–55 are implausible
# for Biosphere 2 soil conditions.
VALUE_T_MIN <- 10
VALUE_T_MAX <- 55
