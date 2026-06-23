#!/usr/bin/env Rscript
#
# process_asd.R — Process ASD Field Spec 3 hyperspectral data
#
# Required packages: dplyr, readr
# Install: install.packages(c("dplyr", "readr"))
#
# Expected reflectance file format (ASD ViewSpec Pro "ProcessedReflectance" export):
#   Tab-delimited; first column = wavelengths (350–2500 nm); remaining columns =
#   one reflectance series per leaf collection (wavelengths as rows, scans as cols).
#
# Run as: Rscript process_asd.R

# ============================================================
#  CONFIGURATION — edit these paths before each run
# ============================================================

date        <- "20260617"   # YYYYMMDD — change this each run

base_path   <- "X:/moore/2026_B2_SoilProp/Data/ASD"

reflectance_file <- file.path(base_path, "ProcessedReflectance",
                               paste0("ProcessedReflectance_", date, ".txt"))
spectral_id_file <- file.path(base_path, "SpectralID",
                               paste0("SpectralID_", date, ".csv"))
output_spectral  <- file.path(base_path, "FullSpectralFieldData",
                               "SpectralFieldData.csv")
output_indices   <- "X:/moore/2026_B2_SoilProp/Code/data/SpectralIndices_FullData.csv"

plant_id_col <- "Genus"   # SpectralID column to use as plant identifier
leaf_col     <- "Leaf#"   # SpectralID column to use as leaf number
group_cols   <- NULL      # set to e.g. "Panel" if needed, otherwise leave NULL

# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# --------------------------------------------------------------------------- #
#  Helper functions                                                            #
# --------------------------------------------------------------------------- #

log_msg <- function(msg) {
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg))
}

# Extract the YYYYMMDD date embedded in a filename like ProcessedReflectance_YYYYMMDD.txt
parse_date_from_filename <- function(path) {
  bn <- basename(path)
  m  <- regmatches(bn, regexpr("[0-9]{8}", bn))
  if (length(m) == 0) {
    stop("Cannot parse YYYYMMDD date from filename: ", bn, call. = FALSE)
  }
  as.Date(m, format = "%Y%m%d")
}

# Read an ASD ProcessedReflectance tab-delimited text file.
# Wavelengths are rows, collections are columns — this function transposes so
# rows = collections and columns are named p350, p351, ..., p2500.
read_reflectance <- function(path) {
  raw <- utils::read.table(
    path, header = TRUE, sep = "\t",
    check.names = FALSE, stringsAsFactors = FALSE
  )

  wl <- suppressWarnings(as.numeric(raw[[1]]))

  if (any(is.na(wl))) {
    stop(
      "Non-numeric values found in the first column of the reflectance file. ",
      "Expected wavelengths (350–2500 nm).",
      call. = FALSE
    )
  }
  if (min(wl) > 400 || max(wl) < 2400) {
    warning(
      sprintf(
        "Wavelength range (%g–%g nm) looks narrower than expected 350–2500 nm.",
        min(wl), max(wl)
      ),
      call. = FALSE
    )
  }

  refl_matrix <- as.matrix(raw[, -1, drop = FALSE])
  storage.mode(refl_matrix) <- "numeric"

  # Transpose: rows become collections; assign wavelength-named column headers
  refl_t <- t(refl_matrix)
  colnames(refl_t) <- paste0("p", round(wl))

  list(data = as.data.frame(refl_t), wl = wl)
}

# Linear interpolation of reflectance at a target wavelength.
# rule = 2 clamps to the nearest boundary when nm falls outside wl_vec range.
get_refl <- function(nm, wl_vec, refl_vec) {
  approx(wl_vec, refl_vec, xout = nm, method = "linear", rule = 2)$y
}

# Calculate all 19 spectral indices from Barnes et al. (2017) Table 1
# for a single leaf collection defined by paired wl_vec / refl_vec vectors.
calc_indices <- function(wl_vec, refl_vec) {
  p <- function(nm) get_refl(nm, wl_vec, refl_vec)

  list(
    SR1              = p(750) / p(700),
    DoubleDifference = (p(749) - p(720)) - (p(701) - p(672)),
    Vogelmann1       = p(740) / p(720),
    mSR705           = (p(750) - p(445)) / (p(705) - p(445)),
    SRCarter         = p(760) / p(695),
    Maccioni         = (p(780) - p(710)) / (p(780) - p(680)),
    SR3              = p(750) / p(550),
    Gitelson         = 1 / p(700),
    NDVI_MODIS       = (p(858) - p(648)) / (p(858) + p(648)),   # NIR=858, Red=648 (MODIS band centres)
    Datt4            = p(672) / (p(550) * p(708)),
    SR4              = p(700) / p(670),
    SR2              = p(752) / p(690),
    NDVI_hyper       = (p(860) - p(690)) / (p(860) + p(690)),
    Vogelmann2       = (p(734) - p(747)) - (p(715) + p(726)),
    mNDVI            = (p(800) - p(680)) / (p(800) + p(680) - 2 * p(445)),
    NDWI             = (p(860) - p(1240)) / (p(860) + p(1240)),
    SIPI             = (p(800) - p(445)) / (p(800) + p(445)),
    PRI              = (p(531) - p(570)) / (p(531) + p(570)),
    mSRCHL           = (p(800) - p(445)) / (p(680) - p(445))
  )
}

# Append a data frame to a CSV; write column headers only when creating the file.
append_csv <- function(df, path) {
  readr::write_csv(df, path, append = file.exists(path))
}

# --------------------------------------------------------------------------- #
#  Step 1 — Read inputs and join row-by-row                                   #
# --------------------------------------------------------------------------- #

log_msg("Step 1: Reading inputs")

if (!file.exists(reflectance_file)) {
  stop("Reflectance file not found: ", reflectance_file, call. = FALSE)
}
if (!file.exists(spectral_id_file)) {
  stop("SpectralID file not found: ", spectral_id_file, call. = FALSE)
}

field_date  <- parse_date_from_filename(reflectance_file)
refl_result <- read_reflectance(reflectance_file)
refl_df     <- refl_result$data
wl_vec      <- refl_result$wl

log_msg(sprintf(
  "  Reflectance: %d collections x %d wavelengths (date: %s)",
  nrow(refl_df), ncol(refl_df), field_date
))

meta_df <- readr::read_csv(spectral_id_file, show_col_types = FALSE)
log_msg(sprintf(
  "  SpectralID: %d rows, columns: %s",
  nrow(meta_df), paste(names(meta_df), collapse = ", ")
))

if (nrow(refl_df) != nrow(meta_df)) {
  stop(sprintf(
    "Row count mismatch: reflectance file has %d collections but SpectralID has %d rows.",
    nrow(refl_df), nrow(meta_df)
  ), call. = FALSE)
}

# Validate and rename config-specified columns to standard names used throughout
missing_cols <- setdiff(c(plant_id_col, leaf_col), names(meta_df))
if (length(missing_cols) > 0) {
  stop(
    "SpectralID CSV is missing column(s) specified in the config block: ",
    paste(missing_cols, collapse = ", "),
    call. = FALSE
  )
}

meta_df <- dplyr::rename(meta_df, plantID = !!plant_id_col, leafNumber = !!leaf_col)

# Resolve extra grouping columns (group_cols may be NULL, a string, or a vector)
extra_grp <- if (is.null(group_cols)) character(0) else as.character(group_cols)

missing_grp <- setdiff(extra_grp, names(meta_df))
if (length(missing_grp) > 0) {
  stop(
    "group_cols column(s) not found in SpectralID CSV: ",
    paste(missing_grp, collapse = ", "),
    call. = FALSE
  )
}

group_key_cols <- c("date", "plantID", extra_grp)

# Row-by-row join: date prepended, SpectralID columns, reflectance columns
joined_df <- dplyr::bind_cols(
  data.frame(date = field_date),
  meta_df,
  refl_df
)

log_msg(sprintf("  Joined: %d rows x %d columns", nrow(joined_df), ncol(joined_df)))

# --------------------------------------------------------------------------- #
#  Step 2 — Append full spectral output                                       #
# --------------------------------------------------------------------------- #

log_msg(sprintf("Step 2: Appending full spectral data to %s", output_spectral))

# Use a regex-based selector to avoid accidentally picking up plantID (starts with "p")
wl_cols      <- grep("^p[0-9]+$", names(joined_df), value = TRUE)
spectral_out <- dplyr::select(
  joined_df,
  date, plantID, leafNumber,
  dplyr::all_of(wl_cols)
)

append_csv(spectral_out, output_spectral)
log_msg(sprintf("  Appended %d rows", nrow(spectral_out)))

# --------------------------------------------------------------------------- #
#  Step 3 — Calculate spectral indices per leaf collection                    #
# --------------------------------------------------------------------------- #

log_msg("Step 3: Calculating spectral indices")

wl_nums <- as.numeric(sub("^p", "", wl_cols))

# Apply calc_indices to each row; lapply keeps the per-row list structure clean
indices_list <- lapply(seq_len(nrow(joined_df)), function(i) {
  refl_row <- as.numeric(joined_df[i, wl_cols])
  as.data.frame(calc_indices(wl_nums, refl_row))
})

indices_df <- dplyr::bind_cols(
  dplyr::select(joined_df, dplyr::all_of(group_key_cols)),
  dplyr::bind_rows(indices_list)
)

log_msg(sprintf("  Calculated 19 indices for %d collections", nrow(indices_df)))

# --------------------------------------------------------------------------- #
#  Step 4 — Summarise indices per plant per date                              #
# --------------------------------------------------------------------------- #

log_msg("Step 4: Summarising indices by plant and date")

index_names <- c(
  "SR1", "DoubleDifference", "Vogelmann1", "mSR705", "SRCarter",
  "Maccioni", "SR3", "Gitelson", "NDVI_MODIS", "Datt4", "SR4",
  "SR2", "NDVI_hyper", "Vogelmann2", "mNDVI", "NDWI", "SIPI",
  "PRI", "mSRCHL"
)

summary_df <- indices_df |>
  dplyr::group_by(dplyr::across(dplyr::all_of(group_key_cols))) |>
  dplyr::summarise(
    dplyr::across(
      dplyr::all_of(index_names),
      list(
        mean = \(x) mean(x, na.rm = TRUE),
        sd   = \(x) sd(x,   na.rm = TRUE)
      ),
      .names = "{.col}_{.fn}"
    ),
    .groups = "drop"
  )

log_msg(sprintf("  Summary: %d plant-date rows", nrow(summary_df)))

# --------------------------------------------------------------------------- #
#  Step 5 — Append indices summary with duplicate guard                       #
# --------------------------------------------------------------------------- #

log_msg(sprintf("Step 5: Appending spectral indices to %s", output_indices))

if (file.exists(output_indices)) {
  existing <- readr::read_csv(output_indices, show_col_types = FALSE)

  dups <- dplyr::semi_join(summary_df, existing, by = group_key_cols)

  if (nrow(dups) > 0) {
    dup_desc <- paste(
      apply(dups[, group_key_cols, drop = FALSE], 1, function(r)
        paste(names(r), r, sep = "=", collapse = "  ")),
      collapse = "\n  "
    )
    warning(
      sprintf(
        "%d duplicate group(s) already in %s — skipping:\n  %s",
        nrow(dups), basename(output_indices), dup_desc
      ),
      call. = FALSE
    )
    summary_df <- dplyr::anti_join(summary_df, existing, by = group_key_cols)
  }
}

if (nrow(summary_df) > 0) {
  append_csv(summary_df, output_indices)
  log_msg(sprintf("  Appended %d row(s)", nrow(summary_df)))
} else {
  log_msg("  No new rows to append (all were duplicates)")
}

log_msg("Done.")
