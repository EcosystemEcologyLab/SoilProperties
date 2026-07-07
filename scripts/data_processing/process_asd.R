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
# Expected SpectralID CSV columns: ID#, Leaf#, Genus, PlantID#, Group
#   PlantID# is the numeric plant identifier carried through as plantID.
#   Genus is descriptive metadata only — not used as an identifier.
#   Group is optional (e.g. full panel vs modified panel). If the column is
#   present but entirely blank/NA for this run, it is dropped from grouping
#   automatically — no manual config needed.
#
# Run from RStudio: open this file and source it (Ctrl+Shift+S / Cmd+Shift+S).

if (!interactive()) {
  stop(
    "This script must be run interactively from RStudio ",
    "(source it, don't Rscript it)."
  )
}

# ============================================================
#  CONFIGURATION — edit these paths before each run
# ============================================================

# Set working directory to this script's location
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
# Terminal users: run from the repo root with
#   Rscript scripts/data_processing/process_asd.R

date <- trimws(readline(
  "Enter the date for this ASD run (YYYYMMDD, e.g. 20261011): "
))
if (nchar(date) != 8 || !grepl("^[0-9]{8}$", date)) {
  stop("Date must be exactly 8 digits in YYYYMMDD format. Got: '", date, "'")
}
date_str <- format(as.Date(date, "%Y%m%d"), "%Y-%m-%d")

.resolve_asd_base_path <- function() {
  win_default <- file.path("X:", "moore", "2026_B2_SoilProp", "Data", "ASD")
  mac_default <- "/Volumes/projects/moore/2026_B2_SoilProp/Data/ASD"
  if (dir.exists(win_default)) return(win_default)
  if (dir.exists(mac_default)) return(mac_default)
  cat(paste0(
    "Could not find the ASD data folder automatically.\n",
    "On Windows, the folder is usually at X:\\moore\\2026_B2_SoilProp\\Data\\ASD\n",
    "On Mac, it may be at /Volumes/projects/moore/... or similar.\n",
    "Enter the full path to the ASD base data folder: "
  ))
  path <- trimws(readline())
  if (!dir.exists(path)) stop("Directory not found: ", path, call. = FALSE)
  path
}
base_path <- .resolve_asd_base_path()
rm(.resolve_asd_base_path)

reflectance_file <- file.path(base_path, "ProcessedReflectance",
                              paste0("ProcessedReflectance_", date, ".txt"))
spectral_id_file <- file.path(base_path, "SpectralID",
                              paste0("SpectralID_", date, ".csv"))
output_spectral  <- file.path(base_path, "FullSpectralFieldData",
                              "SpectralFieldData.csv")
output_indices   <- file.path("data", "Full", "SpectralIndices_FullData.csv")

# plant_id_col: the SpectralID column used as the plant identifier in output.
# PlantID# is the numeric ID (parallel to the 4-digit PlantID used in the
# soil moisture / infiltration pipelines) — Genus is descriptive only and is
# carried through as a separate metadata column, not used as an identifier.
plant_id_col <- "PlantID#"
genus_col    <- "Genus"
leaf_col     <- "Leaf#"

# group_col: optional treatment grouping (e.g. full panel vs modified panel).
# Leave as "Group" to match the SpectralID schema. If this column is present
# but blank/NA for every row in a given run, it is automatically dropped from
# grouping below — no need to edit this per run.
group_col <- "Group"

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
    NDVI_MODIS       = (p(858) - p(648)) / (p(858) + p(648)),
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

# Validate required columns are present before renaming.
# group_col is checked separately below since it's optional.
required_cols <- c(plant_id_col, genus_col, leaf_col)
missing_cols  <- setdiff(required_cols, names(meta_df))
if (length(missing_cols) > 0) {
  stop(
    "SpectralID CSV is missing required column(s): ",
    paste(missing_cols, collapse = ", "),
    call. = FALSE
  )
}

meta_df <- dplyr::rename(
  meta_df,
  plantID    = !!plant_id_col,
  genus      = !!genus_col,
  leafNumber = !!leaf_col
)

# PlantID# should be the numeric identifier — flag (not fail) if it doesn't
# look numeric, since SpectralID is hand-entered field data.
non_numeric_ids <- meta_df$plantID[is.na(suppressWarnings(as.numeric(meta_df$plantID)))]
if (length(non_numeric_ids) > 0) {
  warning(
    sprintf(
      "%d row(s) have a non-numeric PlantID#: %s. Carrying through as-entered.",
      length(non_numeric_ids), paste(unique(non_numeric_ids), collapse = ", ")
    ),
    call. = FALSE
  )
}

# Group is optional. If the column exists but is entirely blank/NA for this
# run, drop it from grouping automatically rather than requiring per-run
# config edits.
has_group_col <- group_col %in% names(meta_df)
if (has_group_col) {
  meta_df        <- dplyr::rename(meta_df, group = !!group_col)
  group_has_data <- any(!is.na(meta_df$group) & trimws(as.character(meta_df$group)) != "")
} else {
  group_has_data <- FALSE
}

use_group <- has_group_col && group_has_data
if (has_group_col && !group_has_data) {
  log_msg("  Group column present but empty for this run — excluding from grouping")
} else if (use_group) {
  log_msg("  Group column has data — including in grouping")
}

group_key_cols <- c("date", "plantID", if (use_group) "group" else NULL)

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
  date, plantID, genus, leafNumber,
  dplyr::any_of("group"),
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
log_msg(sprintf("  Grouping by: %s", paste(group_key_cols, collapse = ", ")))

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
  
  # Only check duplicates against group_key_cols that exist in the existing
  # file too — guards against schema drift if a past run didn't have 'group'.
  dup_check_cols <- intersect(group_key_cols, names(existing))
  
  dups <- dplyr::semi_join(summary_df, existing, by = dup_check_cols)
  
  if (nrow(dups) > 0) {
    dup_desc <- paste(
      apply(dups[, dup_check_cols, drop = FALSE], 1, function(r)
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
    summary_df <- dplyr::anti_join(summary_df, existing, by = dup_check_cols)
  }
}

if (nrow(summary_df) > 0) {
  append_csv(summary_df, output_indices)
  log_msg(sprintf("  Appended %d row(s)", nrow(summary_df)))
} else {
  log_msg("  No new rows to append (all were duplicates)")
}

log_msg("Done.")

# --------------------------------------------------------------------------- #
#  Step 6 — Git workflow                                                      #
# --------------------------------------------------------------------------- #

log_msg("Step 6: Git workflow — next steps")
cat(paste0(
  "\n── Next steps: commit and open a pull request ───────────────────\n",
  "Run these commands in your terminal:\n\n",
  "  git checkout -b data/hyperspectral/", date, "\n",
  "  git add \"", output_spectral, "\" \"", output_indices, "\"\n",
  "  git commit -m \"[data] add hyperspectral ", date_str, "\"\n",
  "  git push -u origin data/hyperspectral/", date, "\n\n",
  "Open a pull request on GitHub for Lindsey to review before merging.\n"
))