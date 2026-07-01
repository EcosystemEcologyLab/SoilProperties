# soilmoisture_config.R
# All configurable constants for the soil moisture cleaning pipeline.
# Changing a threshold is a scientific decision — commit with a clear message.

# ── External paths ─────────────────────────────────────────────────────────────
# DAILY_DATA_DIR: network drive folder containing daily entry .xlsx files.
# Auto-resolved from known Windows (X:) and Mac (/Volumes/projects/...) defaults.
# If neither is found, the user is prompted once per run to enter the path.
.resolve_daily_data_dir <- function() {
  win_default <- file.path("X:", "moore", "2026_B2_SoilProp", "Data",
                           "SoilMoisture", "B2_SoilMoisture_DataSheet_DailyData")
  mac_default <- paste0("/Volumes/projects/moore/2026_B2_SoilProp/Data/",
                        "SoilMoisture/B2_SoilMoisture_DataSheet_DailyData")
  if (dir.exists(win_default)) return(win_default)
  if (dir.exists(mac_default)) return(mac_default)
  if (!interactive()) {
    message("Non-interactive session: DAILY_DATA_DIR not resolved (no server path found).")
    return(NULL)
  }
  cat(paste0(
    "Could not find the soil moisture data folder automatically.\n",
    "On Windows, the folder is usually at ",
    "X:\\moore\\2026_B2_SoilProp\\Data\\SoilMoisture\\B2_SoilMoisture_DataSheet_DailyData\n",
    "On Mac, it may be at /Volumes/projects/moore/... or similar.\n",
    "Enter the full path to the daily data folder: "
  ))
  path <- trimws(readline())
  if (!dir.exists(path)) stop("Directory not found: ", path, call. = FALSE)
  path
}
DAILY_DATA_DIR <- .resolve_daily_data_dir()
rm(.resolve_daily_data_dir)

# MASTER_CSV: git-tracked master data file, relative to project root.
MASTER_CSV  <- file.path("data", "Full", "B2_SoilMoisture_FullData.csv")

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

VALID_PLANTID_CODES <- c("2091", "2417", "2129", "0003", "2139", "2144", "2010",
                         "2085", "2014", "2036", "2005", "2111", "2298", "2079",
                         "2286", "2404", "2274", "0004", "0001", "2234", "2233", 
                         "2393")

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
VALUE_M_MAX <- 50

# Temperature sensor (T): degrees Celsius. Values outside 10–55 are implausible
# for Biosphere 2 soil conditions.
VALUE_T_MIN <- 10
VALUE_T_MAX <- 55
