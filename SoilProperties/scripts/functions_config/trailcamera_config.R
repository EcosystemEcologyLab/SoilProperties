# trailcamera_config.R
# All configurable constants for the trail camera vegetation-index pipeline.
# Changing a threshold is a scientific decision — commit with a clear message.
#
# "THRESHOLD — CONFIRM WITH PI" marks values that are placeholders pending
# PI review before use in production analyses.

# ── Camera identifiers ─────────────────────────────────────────────────────────
# CAMERA_IDS: subdirectory names under RAW_IMAGE_DIR, one per physical camera.
# Validated at pipeline startup by check_trailcamera_config().
CAMERA_IDS <- c("0C", "2C", "3B", "4E", "8E", "8f", "09", "12",
                 "34", "62", "70", "74")

# ── Image quality thresholds ──────────────────────────────────────────────────
# Pixel brightness for valid images (0–255 scale; mean over the image frame).
# Images outside [MIN, MAX] are excluded as too dark or overexposed.
# Units: pixel intensity (0 = black, 255 = white). Valid range: 0–255.
MIN_BRIGHTNESS_0_255 <- 20L   # THRESHOLD — CONFIRM WITH PI
MAX_BRIGHTNESS_0_255 <- 235L  # THRESHOLD — CONFIRM WITH PI

# ── Sampling schedule ─────────────────────────────────────────────────────────
# Time window and interval for images included in the vegetation-index analysis.
# Only images captured between SCHEDULE_START_HOUR and SCHEDULE_END_HOUR
# (inclusive, 24-hour clock) at SCHEDULE_INTERVAL_MIN-minute intervals are used.
# Units: hours (0–23), minutes (1–60).
SCHEDULE_START_HOUR   <- 10L  # 10:00 local time
SCHEDULE_END_HOUR     <- 14L  # 14:00 local time
SCHEDULE_INTERVAL_MIN <- 20L  # images expected every 20 minutes

# ── Raw image directory ────────────────────────────────────────────────────────
# RAW_IMAGE_DIR: root of the trail camera image tree on the network drive.
# Contains one subdirectory per camera ID (see CAMERA_IDS above).
# Resolved in order: TRAILCAM_RAW_IMAGE_DIR env var → interactive readline() prompt.
# Set TRAILCAM_RAW_IMAGE_DIR in your .env file (see .env.example).
.resolve_trailcam_raw_dir <- function() {
  env_path <- Sys.getenv("TRAILCAM_RAW_IMAGE_DIR")
  if (nchar(env_path) > 0 && dir.exists(env_path)) return(env_path)
  if (!interactive()) {
    message("Non-interactive session: TRAILCAM_RAW_IMAGE_DIR is not set or ",
            "does not exist. Set it in your .env file (see .env.example).")
    return(NULL)
  }
  cat(paste0(
    "Could not find the trail camera image folder automatically.\n",
    "Hint: set TRAILCAM_RAW_IMAGE_DIR in your .env file (see .env.example).\n",
    "On Windows, the folder is usually at ",
    "X:\\moore\\2026_B2_SoilProp\\Data\\TrailCamera\n",
    "On Mac, it may be at /Volumes/projects/moore/... or similar.\n",
    "Enter the full path to the trail camera raw image folder: "
  ))
  path <- trimws(readline())
  if (!dir.exists(path)) stop("Directory not found: ", path, call. = FALSE)
  cat(paste0(
    "\nTo skip this prompt in future runs, add this line to your .env file:\n",
    "  TRAILCAM_RAW_IMAGE_DIR=", path, "\n"
  ))
  path
}
RAW_IMAGE_DIR <- .resolve_trailcam_raw_dir()
# .resolve_trailcam_raw_dir is intentionally NOT rm()'d — check_trailcamera_config()
# calls it as its default argument so every no-arg call re-resolves live instead
# of trusting the source-time snapshot in RAW_IMAGE_DIR.

# ── Reference and output paths ────────────────────────────────────────────────
# All paths are relative to the project root. Scripts that source this config
# must set their working directory to the project root first.
ROI_REFERENCE_DIR  <- file.path("data", "reference", "trailcamera")
OVERRIDE_FILE_PATH <- file.path("data", "overrides", "trailcamera_overrides.csv")
EXCLUSION_LOG_PATH <- file.path("outputs", "trailcamera_exclusion_log.csv")
UNKNOWN_LOG_PATH   <- file.path("outputs", "trailcamera_unknown_log.csv")
PROCESSED_DIR      <- file.path("data", "processed", "trailcamera")
FIGURES_DIR        <- file.path("figures", "trailcamera")

# ── Config validator ───────────────────────────────────────────────────────────

#' Verify the trail camera pipeline configuration.
#'
#' Stops loudly if \code{RAW_IMAGE_DIR} is NULL or if any \code{CAMERA_IDS}
#' subfolder is missing under it. Call at the top of every pipeline script that
#' accesses raw trail camera images. Do NOT call in unit tests that check pure
#' logic — it requires the network drive to be mounted.
#'
#' @param raw_dir Root directory to check. Defaults to \code{RAW_IMAGE_DIR}.
#' @return \code{TRUE} invisibly when all checks pass.
check_trailcamera_config <- function(raw_dir = .resolve_trailcam_raw_dir()) {
  if (is.null(raw_dir)) {
    stop(
      "RAW_IMAGE_DIR is NULL — the trail camera image directory has not been ",
      "resolved. Set TRAILCAM_RAW_IMAGE_DIR in your .env file (see .env.example) ",
      "and restart R.",
      call. = FALSE
    )
  }
  missing_cams <- CAMERA_IDS[!dir.exists(file.path(raw_dir, CAMERA_IDS))]
  if (length(missing_cams) > 0) {
    stop(
      "The following CAMERA_IDS subfolders are missing under ", raw_dir, ":\n",
      "  ", paste(missing_cams, collapse = ", "), "\n",
      "Check that the network drive is mounted and TRAILCAM_RAW_IMAGE_DIR ",
      "points to the correct root folder.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
