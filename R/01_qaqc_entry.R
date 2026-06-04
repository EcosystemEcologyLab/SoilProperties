# =============================================================================
# 01_qaqc_entry.R — QA/QC of a daily soil-infiltration field sheet
# -----------------------------------------------------------------------------
# Usage:  Rscript R/01_qaqc_entry.R <path/to/field_sheet.xlsx>
#
# Reads both plot blocks from a Soil_Infiltration field sheet, stacks them into
# long format, applies the QC rules below in order, and writes a cleaned CSV plus
# appends to the exclusion / unknown logs. No record is ever silently dropped —
# every removed row lands in exactly one log (first-failure attribution).
#
# QC order (per project spec):
#   1. Controlled vocabulary (soil_type)         empty -> UNKNOWN; bad -> EXCLUDE
#   2. Numeric ranges (time, volume)             missing -> UNKNOWN; bad -> EXCLUDE
#   3. Monotonic time (non-decreasing)           bad -> EXCLUDE
#   4. Monotonic volume (non-increasing +1 mL)   bad -> EXCLUDE
#   5. Suction in VALID_SUCTIONS_CM              bad -> EXCLUDE whole site-date
#   6. t=0 anchor row present per replicate       missing -> UNKNOWN (drop rep)
#
# Output: data/processed/{site}_{date}_infiltration_clean.csv
# =============================================================================

source("R/pipeline_config.R")

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tidyr)
})

THIS_SCRIPT <- "01_qaqc_entry.R"

# -----------------------------------------------------------------------------
# Field-sheet reader
# -----------------------------------------------------------------------------
# Expected layout (see output_template/Soil_Infiltration_FieldDataSheet_v2.xlsx):
#   * A metadata header block: label in column A, value in column B, for
#     Site, Date, Time Start, Time End, Suction Rate (cm), Observers, Notes.
#   * One or more data blocks, each beginning with a header row that contains
#     the column labels Plot | Point ID | SoilType | Time (sec) | Volume (mL).
#     Data rows follow until a fully blank row. Plot and SoilType may be entered
#     once per block and are forward-filled down the block.
# All cells are read as text and coerced here, so Excel date serials and number
# formatting cannot silently corrupt values.

.norm <- function(x) tolower(trimws(ifelse(is.na(x), "", as.character(x))))

#' Extract a single metadata value by its column-A label (case-insensitive).
.meta_value <- function(raw, label) {
  col1 <- .norm(raw[[1]])
  target <- .norm(label)
  # Prefix match so e.g. label "Suction Rate" finds a cell "Suction Rate (cm)".
  hit <- which(startsWith(col1, target))
  if (length(hit) == 0) return(NA_character_)
  row <- as.character(unlist(raw[hit[1], -1]))
  row <- row[!is.na(row) & nzchar(trimws(row))]
  if (length(row) == 0) NA_character_ else trimws(row[1])
}

#' Read a field sheet into list(meta = <named list>, data = <data.frame>).
#' @param path Path to the .xlsx field sheet.
read_infiltration_sheet <- function(path) {
  if (!file.exists(path)) stop("Field sheet not found: ", path)
  raw <- suppressMessages(readxl::read_excel(
    path, sheet = 1, col_names = FALSE, col_types = "text", .name_repair = "minimal"))
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  meta <- list(
    site        = .meta_value(raw, "Site"),
    date        = .meta_value(raw, "Date"),
    time_start  = .meta_value(raw, "Time Start"),
    time_end    = .meta_value(raw, "Time End"),
    suction_raw = .meta_value(raw, "Suction Rate"),
    observers   = .meta_value(raw, "Observers"),
    notes       = .meta_value(raw, "Notes")
  )

  # Locate data-block header rows: a row containing a "point id" cell.
  norm_mat <- as.data.frame(lapply(raw, .norm), stringsAsFactors = FALSE)
  header_rows <- which(apply(norm_mat, 1, function(r) any(r == "point id")))
  if (length(header_rows) == 0) {
    stop("No data block found: expected a header row containing 'Point ID' in ", path)
  }

  find_col <- function(hdr_norm, patterns) {
    for (p in patterns) {
      idx <- which(grepl(p, hdr_norm))
      if (length(idx) >= 1) return(idx[1])
    }
    NA_integer_
  }

  blocks <- list()
  for (i in seq_along(header_rows)) {
    hr <- header_rows[i]
    hdr <- as.character(norm_mat[hr, ])
    cmap <- list(
      plot       = find_col(hdr, c("^plot$", "plot")),
      point_id   = find_col(hdr, c("point id")),
      soil_type  = find_col(hdr, c("soil ?type")),
      time_s     = find_col(hdr, c("time")),
      volume_ml  = find_col(hdr, c("volume"))
    )
    if (anyNA(unlist(cmap))) {
      stop("Data block at row ", hr, " is missing one of the expected columns ",
           "(Plot, Point ID, SoilType, Time, Volume) in ", path)
    }
    # Data rows: from hr+1 to just before the next header (or end of sheet),
    # stopping at the first fully blank row across the five data columns.
    next_hr <- if (i < length(header_rows)) header_rows[i + 1] - 1 else nrow(raw)
    rng <- seq.int(hr + 1, next_hr)
    block <- data.frame(
      plot      = trimws(as.character(raw[rng, cmap$plot])),
      point_id  = trimws(as.character(raw[rng, cmap$point_id])),
      soil_type = trimws(as.character(raw[rng, cmap$soil_type])),
      time_s    = trimws(as.character(raw[rng, cmap$time_s])),
      volume_ml = trimws(as.character(raw[rng, cmap$volume_ml])),
      stringsAsFactors = FALSE
    )
    block[block == "" | block == "NA"] <- NA
    # Stop at first fully blank data row (end of this block).
    blank <- apply(block, 1, function(r) all(is.na(r)))
    if (any(blank)) block <- block[seq_len(which(blank)[1] - 1), , drop = FALSE]
    if (nrow(block) == 0) next
    # Forward-fill plot and soil_type (entered once per block).
    block <- tidyr::fill(block, plot, soil_type, .direction = "down")
    block$block <- i
    blocks[[length(blocks) + 1]] <- block
  }

  data <- dplyr::bind_rows(blocks)
  list(meta = meta, data = data)
}

# -----------------------------------------------------------------------------
# Helpers for log-row construction (.slug() lives in pipeline_config.R)
# -----------------------------------------------------------------------------
.excl_rows <- function(df, variable, reason, threshold) {
  if (nrow(df) == 0) return(NULL)
  data.frame(
    site_id     = df$site,
    variable    = variable,
    timestamp   = ifelse(is.na(df$time_s), "NA", as.character(df$time_s)),
    reason      = reason,
    threshold   = threshold,
    excluded_by = THIS_SCRIPT,
    stringsAsFactors = FALSE
  )
}

.unk_rows <- function(df, reason) {
  if (nrow(df) == 0) return(NULL)
  data.frame(
    record_id = paste(df$site, df$date, df$plot, df$point_id, sep = "_"),
    reason    = reason,
    logged_by = THIS_SCRIPT,
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# Main QC driver
# -----------------------------------------------------------------------------

#' Run QA/QC on a field sheet and write the cleaned CSV + logs.
#' @param path Path to the daily field sheet (.xlsx).
#' @return Invisibly the path to the cleaned CSV (or NA if nothing passed).
run_qaqc_entry <- function(path) {
  check_pipeline_config()
  ensure_logs_exist()

  parsed <- read_infiltration_sheet(path)
  meta <- parsed$meta
  df <- parsed$data

  if (is.null(df) || nrow(df) == 0) {
    stop("No data rows read from ", path)
  }

  # Broadcast metadata onto every row.
  df$site     <- meta$site
  df$date     <- meta$date
  df$observer <- meta$observers
  df$notes    <- ifelse(is.na(meta$notes), "", meta$notes)
  suction_cm  <- suppressWarnings(as.numeric(meta$suction_raw))
  df$suction_cm <- suction_cm

  n_read <- nrow(df)
  df$.row <- seq_len(n_read)  # entry order, for monotonic checks

  excl <- list(); unk <- list()
  add_excl <- function(x) if (!is.null(x)) excl[[length(excl) + 1]] <<- x
  add_unk  <- function(x) if (!is.null(x)) unk[[length(unk) + 1]]  <<- x

  # ---- 1. Controlled vocabulary (soil_type) -------------------------------
  st_norm <- tolower(trimws(df$soil_type))           # normalise case only
  df$soil_type <- st_norm
  empty_soil <- is.na(st_norm) | st_norm == ""
  add_unk(.unk_rows(df[empty_soil, ], "soil_type_missing"))
  df <- df[!empty_soil, , drop = FALSE]

  bad_soil <- !(df$soil_type %in% VALID_SOIL_TYPES)
  add_excl(.excl_rows(df[bad_soil, ], "soil_type", "soil_type_unrecognised",
                      "VALID_SOIL_TYPES"))
  df <- df[!bad_soil, , drop = FALSE]

  # ---- 2. Numeric ranges (time, volume) -----------------------------------
  df$time_s    <- suppressWarnings(as.numeric(df$time_s))
  df$volume_ml <- suppressWarnings(as.numeric(df$volume_ml))

  miss_time <- is.na(df$time_s)
  add_unk(.unk_rows(df[miss_time, ], "time_missing"))
  df <- df[!miss_time, , drop = FALSE]

  miss_vol <- is.na(df$volume_ml)
  add_unk(.unk_rows(df[miss_vol, ], "volume_missing"))
  df <- df[!miss_vol, , drop = FALSE]

  neg_time <- df$time_s < 0
  add_excl(.excl_rows(df[neg_time, ], "time_s", "time_negative", "Time>=0"))
  df <- df[!neg_time, , drop = FALSE]

  neg_vol <- df$volume_ml < 0
  add_excl(.excl_rows(df[neg_vol, ], "volume_ml", "volume_negative", "Volume>=0"))
  df <- df[!neg_vol, , drop = FALSE]

  over_vol <- df$volume_ml > MAX_VOLUME_ML
  add_excl(.excl_rows(df[over_vol, ], "volume_ml", "volume_exceeds_max",
                      sprintf("Volume<=MAX_VOLUME_ML=%g", MAX_VOLUME_ML)))
  df <- df[!over_vol, , drop = FALSE]

  # ---- 3 & 4. Monotonicity within (site, date, plot, point_id) ------------
  # Evaluate in entry order. A reading is bad if it breaks the sequence
  # relative to the previous kept reading in the same replicate.
  if (nrow(df) > 0) {
    df <- df[order(df$site, df$date, df$plot, df$point_id, df$.row), , drop = FALSE]
    grp <- interaction(df$site, df$date, df$plot, df$point_id, drop = TRUE)

    # 3. time non-decreasing: flag rows where time < previous time in group
    prev_time <- ave(df$time_s, grp, FUN = function(v) c(NA, head(v, -1)))
    bad_time <- !is.na(prev_time) & df$time_s < prev_time
    add_excl(.excl_rows(df[bad_time, ], "time_s", "non_monotonic_time",
                        "strictly_non_decreasing"))
    df <- df[!bad_time, , drop = FALSE]

    # 4. volume non-increasing (+ tolerance): flag rows where volume rises
    #    by more than VOL_MONOTONIC_TOLERANCE_ML vs previous reading in group
    grp <- interaction(df$site, df$date, df$plot, df$point_id, drop = TRUE)
    prev_vol <- ave(df$volume_ml, grp, FUN = function(v) c(NA, head(v, -1)))
    bad_vol <- !is.na(prev_vol) &
      (df$volume_ml - prev_vol) > VOL_MONOTONIC_TOLERANCE_ML
    add_excl(.excl_rows(df[bad_vol, ], "volume_ml", "non_monotonic_volume",
                        sprintf("VOL_MONOTONIC_TOLERANCE_ML=%g",
                                VOL_MONOTONIC_TOLERANCE_ML)))
    df <- df[!bad_vol, , drop = FALSE]
  }

  # ---- 5. Suction (site-date metadata) ------------------------------------
  # Suction applies to the whole site-date. If invalid, exclude everything.
  suction_ok <- !is.na(suction_cm) &&
    any(abs(suction_cm - VALID_SUCTIONS_CM) < 1e-9)
  if (!suction_ok) {
    # one site-date-level exclusion row, then drop all remaining records
    add_excl(data.frame(
      site_id     = meta$site,
      variable    = "ALL",
      timestamp   = "ALL",
      reason      = "suction_invalid",
      threshold   = paste0("VALID_SUCTIONS_CM in {",
                           paste(VALID_SUCTIONS_CM, collapse = ","), "}"),
      excluded_by = THIS_SCRIPT,
      stringsAsFactors = FALSE))
    df <- df[0, , drop = FALSE]
  }

  # ---- 6. t=0 anchor required per replicate -------------------------------
  if (nrow(df) > 0) {
    has_t0 <- df %>%
      group_by(site, date, plot, point_id) %>%
      summarise(t0 = any(time_s == 0), .groups = "drop")
    no_anchor <- has_t0[!has_t0$t0, c("site", "date", "plot", "point_id")]
    if (nrow(no_anchor) > 0) {
      add_unk(.unk_rows(no_anchor, "no_t0_anchor"))
      df <- df %>% anti_join(no_anchor, by = c("site", "date", "plot", "point_id"))
    }
  }

  # ---- Assemble logs and write --------------------------------------------
  excl_df <- if (length(excl)) dplyr::bind_rows(excl) else NULL
  unk_df  <- if (length(unk))  dplyr::bind_rows(unk)  else NULL
  log_exclusions(excl_df)
  log_unknowns(unk_df)

  n_excluded <- if (is.null(excl_df)) 0L else nrow(excl_df)
  n_unknown  <- if (is.null(unk_df))  0L else nrow(unk_df)

  clean <- df %>%
    transmute(site, date, plot, point_id, soil_type, suction_cm,
              time_s, volume_ml, observer, notes) %>%
    arrange(site, date, plot, point_id, time_s)

  dir.create(PATH_PROCESSED, showWarnings = FALSE, recursive = TRUE)
  out_path <- file.path(
    PATH_PROCESSED,
    sprintf("%s_%s_infiltration_clean.csv", .slug(meta$site), .slug(meta$date)))
  write.csv(clean, out_path, row.names = FALSE, na = "")

  message(sprintf(
    "Script 01 complete: %d records read, %d passed, %d excluded, %d unknown",
    n_read, nrow(clean), n_excluded, n_unknown))
  message("  -> ", out_path)

  invisible(out_path)
}

# Run only when invoked via Rscript (not when source()'d by tests).
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript R/01_qaqc_entry.R <path/to/field_sheet.xlsx>")
  }
  run_qaqc_entry(args[1])
}
