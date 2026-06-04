# =============================================================================
# pipeline_config.R — Soil Infiltration pipeline configuration
# -----------------------------------------------------------------------------
# Named constants, reference-table loaders, and the configuration self-check for
# the B2 soil-infiltration pipeline (MiniDisk infiltrometer -> K via the van
# Genuchten / Zhang 1997 method).
#
# Every numbered script must begin with:
#     source("R/pipeline_config.R")
#     check_pipeline_config()
#
# Per SCIENCE_PRINCIPLES_PIPELINES.md: all scientifically meaningful thresholds
# are declared here as named constants documented with units, valid range,
# default, and rationale — never as magic numbers inline in scripts.
#
# Scripts are expected to be run from the project root, so paths are relative.
# =============================================================================

# (No library() calls here — config relies only on base R. Scripts that need
#  readxl/openxlsx/dplyr/etc. load them after sourcing this file.)

# -----------------------------------------------------------------------------
# Project paths (relative to project root — no absolute paths per principles)
# -----------------------------------------------------------------------------
PATH_REFERENCE      <- "data/reference"
PATH_VG_PARAMS      <- file.path(PATH_REFERENCE, "vg_parameters.csv")
PATH_RADII          <- file.path(PATH_REFERENCE, "infiltrometer_radii.csv")
PATH_PROCESSED      <- "data/processed"
PATH_OVERRIDES      <- "data/overrides"
PATH_OUTPUTS        <- "outputs"
PATH_FIGURES        <- "figures"
PATH_EXCLUSION_LOG  <- file.path(PATH_OUTPUTS, "exclusion_log.csv")
PATH_UNKNOWN_LOG    <- file.path(PATH_OUTPUTS, "unknown_log.csv")
PATH_SESSION_INFO   <- file.path(PATH_OUTPUTS, "session_info.txt")
PATH_FULLDATA       <- file.path(PATH_PROCESSED, "B2_SoilInfiltration_FullData.xlsx")

# -----------------------------------------------------------------------------
# Instrument constants
# -----------------------------------------------------------------------------

# INFILTROMETER_TYPE
#   Units:    categorical (must match a row in infiltrometer_radii.csv)
#   Valid:    "MiniDisk" | "MiniDisk Version1"
#   Default:  "MiniDisk"
#   Rationale: The standard METER MiniDisk infiltrometer is the field instrument
#              for this project. Version1 is the older, smaller-disk model;
#              switching is a deliberate per-project decision.
INFILTROMETER_TYPE <- "MiniDisk"

# RADIUS_CM
#   Units:    cm
#   Valid:    > 0 (looked up from infiltrometer_radii.csv for INFILTROMETER_TYPE)
#   Default:  2.25 (MiniDisk)
#   Rationale: Disk radius enters the cumulative-infiltration normalisation
#              I_t = (V0 - V_t) / (pi * r^2). Sourced from the reference table
#              rather than hardcoded so the two instrument models stay traceable.
#   NOTE: assigned by load_infiltrometer_radius() below, after the table loads.
RADIUS_CM <- NA_real_

# MAX_VOLUME_ML
#   Units:    mL
#   Valid:    0 <= volume <= 95
#   Default:  95
#   Rationale: Mini Disk reservoir capacity. Readings above this likely indicate
#              a unit error or a refill event. Flagged for human review via the
#              exclusion log rather than auto-corrected.
MAX_VOLUME_ML <- 95

# VALID_SUCTIONS_CM
#   Units:    cm (suction entered as a positive number; h0 = -suction)
#   Valid:    one of the listed settings
#   Default:  the eight selectable settings
#   Rationale: The MiniDisk suction control offers these discrete settings
#              (METER sheet "Experimental Parameters"). Suction is a site-date
#              metadata field, not a per-point value.
VALID_SUCTIONS_CM <- c(0.5, 1, 2, 3, 4, 5, 6, 7)

# VOL_MONOTONIC_TOLERANCE_ML
#   Units:    mL
#   Valid:    >= 0
#   Default:  1
#   Rationale: Reservoir volume should be non-increasing as water infiltrates.
#              A rise of more than this tolerance between successive readings is
#              flagged as non_monotonic_volume. 1 mL allows for reading parallax.
#              (Confirmed with the scientist, 2026-06-02.)
VOL_MONOTONIC_TOLERANCE_ML <- 1

# -----------------------------------------------------------------------------
# Curve-fit / quality constants
# -----------------------------------------------------------------------------

# MIN_FIT_POINTS
#   Units:    count
#   Valid:    >= 2 (the fit has two free parameters: C1, C2)
#   Default:  5
#   Rationale: Minimum points for a defensible I = C1*sqrt(t) + C2*t fit. Below
#              this, K is reported as UNKNOWN (NA) and the replicate is written
#              to the unknown log — never silently dropped.
MIN_FIT_POINTS <- 5

# MIN_FIT_R2
#   Units:    dimensionless (coefficient of determination, 0-1)
#   Valid:    0 <= r2 <= 1
#   Default:  0.95  (project value for B2 soils; the generic placeholder was 0.90)
#   Rationale: Fit-quality floor. Below this the replicate is flagged
#              REVIEW_low_r2 (MEDIUM confidence) but NOT excluded — the scientist
#              reviews it. Set to 0.95 for B2 soils by the scientist (2026-06-02).
MIN_FIT_R2 <- 0.95

# -----------------------------------------------------------------------------
# Reference-table loaders
# -----------------------------------------------------------------------------

#' Load the van Genuchten parameter table.
#'
#' @return data.frame with columns soil_type, alpha, n.
load_vg_parameters <- function() {
  if (!file.exists(PATH_VG_PARAMS)) {
    stop("Missing reference table: ", PATH_VG_PARAMS,
         "\n  This file is git-tracked and required. See data/reference/README.md.")
  }
  read.csv(PATH_VG_PARAMS, stringsAsFactors = FALSE)
}

#' Load the infiltrometer radius table.
#'
#' @return data.frame with columns infiltrometer_type, radius_cm.
load_infiltrometer_radii <- function() {
  if (!file.exists(PATH_RADII)) {
    stop("Missing reference table: ", PATH_RADII,
         "\n  This file is git-tracked and required. See data/reference/README.md.")
  }
  read.csv(PATH_RADII, stringsAsFactors = FALSE)
}

#' Look up the disk radius (cm) for a given infiltrometer type.
#'
#' @param type Character; infiltrometer model. Defaults to INFILTROMETER_TYPE.
#' @return Numeric radius in cm.
load_infiltrometer_radius <- function(type = INFILTROMETER_TYPE) {
  radii <- load_infiltrometer_radii()
  hit <- radii$radius_cm[radii$infiltrometer_type == type]
  if (length(hit) != 1) {
    stop("INFILTROMETER_TYPE '", type, "' not found (exactly once) in ", PATH_RADII,
         ". Available: ", paste(radii$infiltrometer_type, collapse = ", "))
  }
  hit
}

#' Controlled vocabulary of soil types (lowercase), derived from vg_parameters.csv.
#'
#' Never hardcoded — read from the reference table per the spec.
#' @return Character vector of valid soil types, lowercased.
valid_soil_types <- function() {
  tolower(trimws(load_vg_parameters()$soil_type))
}

# -----------------------------------------------------------------------------
# Configuration self-check
# -----------------------------------------------------------------------------

#' Validate the pipeline configuration and load derived constants.
#'
#' Confirms the reference CSVs exist with the expected columns and that the
#' active infiltrometer radius resolves. Assigns RADIUS_CM and VALID_SOIL_TYPES
#' into the global environment for downstream scripts. Fails loudly (stop()) on
#' any problem, per SCIENCE_PRINCIPLES.md "Fail loudly, never silently".
#'
#' @return Invisibly TRUE on success.
check_pipeline_config <- function() {
  # --- reference tables present with expected columns ---
  vg <- load_vg_parameters()
  vg_expected <- c("soil_type", "alpha", "n")
  if (!all(vg_expected %in% names(vg))) {
    stop("vg_parameters.csv is missing expected columns. Found: ",
         paste(names(vg), collapse = ", "),
         " | Expected: ", paste(vg_expected, collapse = ", "))
  }
  if (nrow(vg) == 0) stop("vg_parameters.csv has no rows.")
  if (any(is.na(vg$alpha)) || any(is.na(vg$n))) {
    stop("vg_parameters.csv contains NA in alpha or n.")
  }

  radii <- load_infiltrometer_radii()
  radii_expected <- c("infiltrometer_type", "radius_cm")
  if (!all(radii_expected %in% names(radii))) {
    stop("infiltrometer_radii.csv is missing expected columns. Found: ",
         paste(names(radii), collapse = ", "),
         " | Expected: ", paste(radii_expected, collapse = ", "))
  }

  # --- resolve and publish derived constants ---
  RADIUS_CM <<- load_infiltrometer_radius(INFILTROMETER_TYPE)
  if (!is.finite(RADIUS_CM) || RADIUS_CM <= 0) {
    stop("Resolved RADIUS_CM is not a positive finite number: ", RADIUS_CM)
  }
  VALID_SOIL_TYPES <<- valid_soil_types()

  message(sprintf(
    "Pipeline config OK: %d soil types, infiltrometer=%s (r=%.2f cm), MIN_FIT_R2=%.2f, MIN_FIT_POINTS=%d",
    length(VALID_SOIL_TYPES), INFILTROMETER_TYPE, RADIUS_CM, MIN_FIT_R2, MIN_FIT_POINTS))

  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# Exclusion / unknown logging (shared by scripts 01, 02, 03)
# -----------------------------------------------------------------------------
# Columns follow SCIENCE_PRINCIPLES_PIPELINES.md:
#   exclusion_log.csv : site_id, variable, timestamp, reason, threshold, excluded_by
#   unknown_log.csv   : record_id, reason, logged_by
# Both are append-mode (per spec); the header is written when the file is new.
# Both logs are always created (even with zero data rows) so an empty run still
# produces them, per the "write both logs even if empty" rule.

EXCLUSION_LOG_COLS <- c("site_id", "variable", "timestamp",
                        "reason", "threshold", "excluded_by")
UNKNOWN_LOG_COLS   <- c("record_id", "reason", "logged_by")

#' Append rows to a CSV, writing the header only when the file is new.
#' @param df data.frame of rows to append (may have zero rows).
#' @param path Destination CSV path.
#' @param cols Expected column order.
.append_log <- function(df, path, cols) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  is_new <- !file.exists(path)
  if (is.null(df) || nrow(df) == 0) {
    df <- df[0, , drop = FALSE]
  }
  df <- df[, cols, drop = FALSE]
  write.table(df, path, sep = ",", row.names = FALSE,
              col.names = is_new, append = !is_new, qmethod = "double",
              na = "")
  invisible(path)
}

#' Ensure both logs exist (header-only if absent). Idempotent.
ensure_logs_exist <- function() {
  if (!file.exists(PATH_EXCLUSION_LOG)) {
    .append_log(data.frame(matrix(ncol = length(EXCLUSION_LOG_COLS), nrow = 0,
                 dimnames = list(NULL, EXCLUSION_LOG_COLS)), check.names = FALSE),
                PATH_EXCLUSION_LOG, EXCLUSION_LOG_COLS)
  }
  if (!file.exists(PATH_UNKNOWN_LOG)) {
    .append_log(data.frame(matrix(ncol = length(UNKNOWN_LOG_COLS), nrow = 0,
                 dimnames = list(NULL, UNKNOWN_LOG_COLS)), check.names = FALSE),
                PATH_UNKNOWN_LOG, UNKNOWN_LOG_COLS)
  }
  invisible(TRUE)
}

#' Append a batch of exclusions to outputs/exclusion_log.csv.
#' @param df data.frame with columns site_id, variable, timestamp, reason,
#'   threshold, excluded_by.
log_exclusions <- function(df) .append_log(df, PATH_EXCLUSION_LOG, EXCLUSION_LOG_COLS)

#' Append a batch of unknowns to outputs/unknown_log.csv.
#' @param df data.frame with columns record_id, reason, logged_by.
log_unknowns <- function(df) .append_log(df, PATH_UNKNOWN_LOG, UNKNOWN_LOG_COLS)

# -----------------------------------------------------------------------------
# Misc helpers
# -----------------------------------------------------------------------------

#' Filesystem-safe slug from a label (lowercase, non-alphanumerics -> "_").
#' @param x Character scalar (e.g. a site name or date).
#' @return Character slug.
.slug <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_|_$", "", x)
}
