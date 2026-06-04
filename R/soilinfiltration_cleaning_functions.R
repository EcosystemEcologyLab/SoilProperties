# soilinfiltration_cleaning_functions.R
# Helper functions for clean_soilinfiltration.R.
# Source soilinfiltration_config.R before sourcing this file.

# ── Step 0: Filename parsing ───────────────────────────────────────────────────

#' Parse the field date from a daily entry filename
#'
#' @param filename Character. Bare filename or full path, e.g.
#'   \code{"Soil_Infiltration_FieldData_20260601.xlsx"}.
#' @return A \code{Date} object.
#' @examples
#' parse_date_from_filename("Soil_Infiltration_FieldData_20260601.xlsx")
parse_date_from_filename <- function(filename) {
  base <- basename(filename)
  m <- regmatches(base, regexpr("\\d{8}", base))
  if (length(m) == 0) {
    stop("Cannot parse 8-digit date from filename: ", base,
         "\nExpected format: Soil_Infiltration_FieldData_YYYYMMDD.xlsx")
  }
  d <- suppressWarnings(as.Date(m, format = "%Y%m%d"))
  if (is.na(d)) {
    stop("Date string '", m, "' in filename '", base, "' is not a valid calendar date.")
  }
  d
}

# ── Step 1: Sheet reading and double-entry comparison ─────────────────────────

#' Read Sheet1 and Sheet2 from a daily entry workbook
#'
#' Both sheets must have columns: Site, Subplot, SuctionRate, Time, Volume,
#' SoilMoisture_12cm. SoilMoisture_12cm is a reference measurement recorded
#' alongside the infiltration run — it is read through to the master CSV but
#' receives no range checks or monotonicity checks in this pipeline.
#'
#' @param filepath Character. Full path to the .xlsx file.
#' @return Named list with elements \code{sheet1} and \code{sheet2}, each a
#'   data frame with columns Site, Subplot, SuctionRate, Time, Volume,
#'   SoilMoisture_12cm.
read_entry_sheets <- function(filepath) {
  if (!file.exists(filepath)) {
    stop("File not found: ", filepath)
  }
  expected_cols <- c("Site", "Subplot", "SuctionRate", "Time", "Volume",
                     "SoilMoisture_12cm")

  read_one <- function(sheet_num, label) {
    df <- tryCatch(
      openxlsx::read.xlsx(filepath, sheet = sheet_num),
      error = function(e) {
        stop("Cannot read ", label, " from: ", filepath, "\n", conditionMessage(e))
      }
    )
    missing <- setdiff(expected_cols, names(df))
    if (length(missing) > 0) {
      stop(label, " is missing expected column(s): ", paste(missing, collapse = ", "))
    }
    df[, expected_cols]
  }

  list(
    sheet1 = read_one(1, "Sheet1"),
    sheet2 = read_one(2, "Sheet2")
  )
}

#' Detect cell-level mismatches between Sheet1 and Sheet2
#'
#' Compares values as-entered (no normalisation). Classifies each mismatch so
#' that invisible differences (trailing spaces, case) are immediately apparent
#' to the user. Values are quoted in the output so whitespace is visible.
#' SoilMoisture_12cm is included in the comparison — a transcription error in
#' a reference column should still be caught at double-entry.
#'
#' @param sheet1 Data frame from Sheet1.
#' @param sheet2 Data frame from Sheet2. Must have the same columns as sheet1.
#' @return Data frame with columns \code{row}, \code{column},
#'   \code{sheet1_value}, \code{sheet2_value}, \code{mismatch_type}.
#'   Zero rows means the sheets are identical.
detect_sheet_mismatches <- function(sheet1, sheet2) {
  cols <- names(sheet1)
  rows <- list()

  for (col in cols) {
    v1 <- as.character(sheet1[[col]])
    v2 <- as.character(sheet2[[col]])

    for (i in seq_along(v1)) {
      r1 <- v1[i]; r2 <- v2[i]
      if (identical(r1, r2)) next

      t1 <- trimws(r1); t2 <- trimws(r2)

      mtype <- if (identical(t1, t2)) {
        "whitespace"
      } else if (identical(tolower(t1), tolower(t2))) {
        "case"
      } else {
        "value"
      }

      rows[[length(rows) + 1]] <- data.frame(
        row           = i,
        column        = col,
        sheet1_value  = paste0('"', r1, '"'),  # quotes expose trailing spaces
        sheet2_value  = paste0('"', r2, '"'),
        mismatch_type = mtype,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(data.frame(
      row = integer(0), column = character(0),
      sheet1_value = character(0), sheet2_value = character(0),
      mismatch_type = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

#' Compare Sheet1 and Sheet2, stopping loudly on any mismatch
#'
#' @param sheet1 Data frame from Sheet1.
#' @param sheet2 Data frame from Sheet2.
#' @return Invisible \code{sheet1} when the sheets agree.
compare_sheets <- function(sheet1, sheet2) {
  n1 <- nrow(sheet1); n2 <- nrow(sheet2)
  if (n1 != n2) {
    stop(
      "Row count mismatch: Sheet1 has ", n1, " row(s), Sheet2 has ", n2, " row(s).\n",
      "Fix the source .xlsx and re-run. The script never writes to the entry file."
    )
  }

  mismatches <- detect_sheet_mismatches(sheet1, sheet2)

  if (nrow(mismatches) > 0) {
    message("Sheet mismatch — ", nrow(mismatches), " cell(s) differ:\n")
    print(mismatches, row.names = FALSE)
    stop(
      "\n", nrow(mismatches), " mismatch(es) between Sheet1 and Sheet2.\n",
      "Fix the source .xlsx and re-run. The script never writes to the entry file."
    )
  }

  invisible(sheet1)
}

# ── Step 2: Range and code validation ─────────────────────────────────────────

#' Validate the date parsed from the filename
#'
#' @param date A \code{Date} object.
#' @return Character vector of violation messages. Empty means the date is valid.
validate_date <- function(date) {
  violations <- character(0)
  yr <- as.integer(format(date, "%Y"))

  if (yr != SEASON_YEAR) {
    violations <- c(violations,
      paste0("Year is ", yr, "; expected ", SEASON_YEAR, "."))
  }
  if (date < SEASON_START || date > SEASON_END) {
    violations <- c(violations,
      paste0("Date ", format(date), " is outside the season window ",
             format(SEASON_START), " to ", format(SEASON_END), " (inclusive)."))
  }
  violations
}

#' Detect per-row validation violations
#'
#' Every rule is checked for every row; all failures for a row are collected
#' before moving on. A blank or NA cell is UNKNOWN, not zero — reported as
#' missing. Whitespace is stripped for the categorical lookups only.
#'
#' SoilMoisture_12cm receives NO checks — it is a reference measurement
#' (soil moisture at the time of the infiltration run) that is carried through
#' to the master CSV unchanged. Range or device-specific limits for that sensor
#' are managed by the soil moisture pipeline.
#'
#' @param data Data frame with columns Site, Subplot, SuctionRate, Time,
#'   Volume, SoilMoisture_12cm.
#' @return Data frame with columns \code{row}, \code{rule}, \code{observed_value}.
#'   Zero rows means all rows pass.
detect_row_violations <- function(data) {
  violations <- list()

  add <- function(row, rule, val) {
    violations[[length(violations) + 1]] <<- data.frame(
      row            = row,
      rule           = rule,
      observed_value = as.character(val),
      stringsAsFactors = FALSE
    )
  }

  is_blank <- function(x) is.na(x) || trimws(as.character(x)) == ""

  for (i in seq_len(nrow(data))) {
    site     <- data$Site[i]
    subplot  <- data$Subplot[i]
    suction  <- data$SuctionRate[i]
    time_val <- data$Time[i]
    volume   <- data$Volume[i]
    # SoilMoisture_12cm: no checks (reference column only)

    # ── Missing / blank ──────────────────────────────────────────────────────
    if (is_blank(site))     add(i, "Site: missing (blank/NA)",        site)
    if (is_blank(subplot))  add(i, "Subplot: missing (blank/NA)",     subplot)
    if (is_blank(suction))  add(i, "SuctionRate: missing (blank/NA)", suction)
    if (is_blank(time_val)) add(i, "Time: missing (blank/NA)",        time_val)
    if (is_blank(volume))   add(i, "Volume: missing (blank/NA)",      volume)

    subplot_present <- !is_blank(subplot)
    suction_present <- !is_blank(suction)
    time_present    <- !is_blank(time_val)
    volume_present  <- !is_blank(volume)

    # ── Subplot ───────────────────────────────────────────────────────────────
    if (subplot_present && !trimws(subplot) %in% VALID_SUBPLOTS) {
      add(i, paste0("Subplot: must be one of {",
                    paste(VALID_SUBPLOTS, collapse = ", "), "}"), subplot)
    }

    # ── SuctionRate ───────────────────────────────────────────────────────────
    if (suction_present) {
      s_num <- suppressWarnings(as.numeric(suction))
      if (is.na(s_num)) {
        add(i, "SuctionRate: not numeric", suction)
      } else if (!any(abs(s_num - VALID_SUCTIONS_CM) < 1e-9)) {
        add(i, paste0("SuctionRate: must be one of {",
                      paste(VALID_SUCTIONS_CM, collapse = ", "), "} cm"), suction)
      }
    }

    # ── Time ──────────────────────────────────────────────────────────────────
    if (time_present) {
      t_num <- suppressWarnings(as.numeric(time_val))
      if (is.na(t_num)) {
        add(i, "Time: not numeric", time_val)
      } else if (t_num < 0) {
        add(i, "Time: negative value", time_val)
      } else if (t_num > TIME_MAX_S) {
        add(i, paste0("Time: exceeds TIME_MAX_S (", TIME_MAX_S, " s)"), time_val)
      }
    }

    # ── Volume ────────────────────────────────────────────────────────────────
    if (volume_present) {
      v_num <- suppressWarnings(as.numeric(volume))
      if (is.na(v_num)) {
        add(i, "Volume: not numeric", volume)
      } else if (v_num < 0) {
        add(i, "Volume: negative value", volume)
      } else if (v_num > MAX_VOLUME_ML) {
        add(i, paste0("Volume: exceeds MAX_VOLUME_ML (", MAX_VOLUME_ML, " mL)"), volume)
      }
    }
  }

  if (length(violations) == 0) {
    return(data.frame(
      row = integer(0), rule = character(0), observed_value = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, violations)
}

#' Detect replicate-level validation violations
#'
#' Replicates are groups of rows sharing the same Site and Subplot. Checks:
#' \enumerate{
#'   \item Each replicate must have exactly one row with Time == 0 (the V0 anchor).
#'   \item Within a replicate, Time must be strictly increasing in row order.
#'   \item Within a replicate, Volume must be non-increasing within
#'     \code{VOL_MONOTONIC_TOLERANCE_ML}.
#'   \item All rows in a replicate must share the same SuctionRate (suction is
#'     a fixed setting for the entire measurement run).
#' }
#'
#' Row-level violations (missing/non-numeric values) must be resolved first —
#' \code{validate_rows()} short-circuits: if \code{detect_row_violations()} finds
#' anything, this function is not called. See \code{validate_rows()}.
#'
#' @param data Data frame with columns Site, Subplot, SuctionRate, Time, Volume
#'   (all present and parseable — row-level checks already passed).
#' @return Data frame with columns \code{row}, \code{rule}, \code{observed_value}.
#'   Zero rows means all replicates pass.
detect_replicate_violations <- function(data) {
  violations <- list()

  add <- function(row, rule, val) {
    violations[[length(violations) + 1]] <<- data.frame(
      row            = row,
      rule           = rule,
      observed_value = as.character(val),
      stringsAsFactors = FALSE
    )
  }

  data$Time   <- as.numeric(data$Time)
  data$Volume <- as.numeric(data$Volume)

  rep_groups <- split(seq_len(nrow(data)),
                      paste(data$Site, data$Subplot, sep = "\t"))

  for (idx in rep_groups) {
    d    <- data[idx, , drop = FALSE]
    site <- d$Site[1]; subplot <- d$Subplot[1]
    label <- paste0("(Site=", site, ", Subplot=", subplot, ")")

    # ── t=0 anchor ────────────────────────────────────────────────────────────
    n_t0 <- sum(d$Time == 0, na.rm = TRUE)
    if (n_t0 == 0) {
      add(idx[1],
          paste0("missing t=0 anchor within ", label),
          "no row with Time == 0")
    } else if (n_t0 > 1) {
      add(idx[which(d$Time == 0)[2]],
          paste0("duplicate t=0 anchor within ", label),
          paste0(n_t0, " rows with Time == 0"))
    }

    # ── Monotonic Time (strictly increasing in row order) ─────────────────────
    for (k in seq_len(nrow(d) - 1)) {
      if (d$Time[k + 1] <= d$Time[k]) {
        add(idx[k + 1],
            paste0("non-monotonic Time within ", label),
            paste0(d$Time[k + 1], " <= previous ", d$Time[k]))
        break   # report only the first offending row per replicate
      }
    }

    # ── Monotonic Volume (non-increasing + tolerance) ─────────────────────────
    for (k in seq_len(nrow(d) - 1)) {
      rise <- d$Volume[k + 1] - d$Volume[k]
      if (rise > VOL_MONOTONIC_TOLERANCE_ML) {
        add(idx[k + 1],
            paste0("non-monotonic Volume within ", label),
            paste0(d$Volume[k + 1], " > previous ", d$Volume[k],
                   " + tolerance ", VOL_MONOTONIC_TOLERANCE_ML))
        break
      }
    }

    # ── Consistent SuctionRate within replicate ───────────────────────────────
    unique_suctions <- unique(as.numeric(d$SuctionRate))
    if (length(unique_suctions) > 1) {
      add(idx[1],
          paste0("SuctionRate inconsistent within ", label),
          paste(unique_suctions, collapse = ", "))
    }
  }

  if (length(violations) == 0) {
    return(data.frame(
      row = integer(0), rule = character(0), observed_value = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, violations)
}

#' Validate date and all rows, stopping loudly on any violation
#'
#' Per-row checks run first; if any row-level violation exists, replicate checks
#' are skipped. This short-circuit prevents grouping errors (e.g. a missing
#' Subplot would crash the replicate grouping in detect_replicate_violations()).
#'
#' @param data Data frame with columns Site, Subplot, SuctionRate, Time, Volume,
#'   SoilMoisture_12cm.
#' @param date A \code{Date} object from the filename.
#' @return Invisible \code{data} when all checks pass.
validate_rows <- function(data, date) {
  date_viols <- validate_date(date)
  if (length(date_viols) > 0) {
    stop(
      "Date validation failed:\n  ", paste(date_viols, collapse = "\n  "),
      "\nFix the filename and re-run."
    )
  }

  row_viols <- detect_row_violations(data)
  if (nrow(row_viols) > 0) {
    message("Validation failed — ", nrow(row_viols), " violation(s):\n")
    print(row_viols, row.names = FALSE)
    stop(
      "\n", nrow(row_viols), " validation violation(s) found.\n",
      "Fix the source .xlsx and re-run."
    )
  }

  rep_viols <- detect_replicate_violations(data)
  if (nrow(rep_viols) > 0) {
    message("Replicate validation failed — ", nrow(rep_viols), " violation(s):\n")
    print(rep_viols, row.names = FALSE)
    stop(
      "\n", nrow(rep_viols), " replicate violation(s) found.\n",
      "Fix the source .xlsx and re-run."
    )
  }

  invisible(data)
}

# ── Step 3: Append to master ───────────────────────────────────────────────────

#' Check for an existing date in the master CSV and confirm replacement
#'
#' @param master_csv_path Character. Path to \code{B2_SoilInfiltration_FullData.csv}.
#' @param date A \code{Date} object.
#' @param confirm_fn Function used to prompt the user; defaults to
#'   \code{readline}. Override in tests to avoid interactive blocking.
#' @return \code{FALSE} if the date is not yet in the master (plain append).
#'   \code{TRUE} if the date exists and the user confirmed replacement.
#'   Calls \code{stop()} if the user declines.
check_duplicate_date <- function(master_csv_path, date, confirm_fn = readline) {
  if (!file.exists(master_csv_path)) return(FALSE)

  master <- utils::read.csv(master_csv_path, stringsAsFactors = FALSE)
  if (!"Date" %in% names(master)) return(FALSE)

  existing <- master[master$Date == format(date), ]
  if (nrow(existing) == 0) return(FALSE)

  message("WARNING: ", nrow(existing), " row(s) for ", format(date),
          " already exist in the master CSV:\n")
  print(existing, row.names = FALSE)

  answer <- confirm_fn(
    paste0("\nReplace all ", nrow(existing), " existing row(s) for ",
           format(date), "? [Y/N]: ")
  )

  if (toupper(trimws(answer)) != "Y") {
    stop("Append cancelled. No changes made to the master CSV.")
  }
  TRUE
}

#' Append validated rows to the master CSV
#'
#' @param data Data frame with columns Site, Subplot, SuctionRate, Time, Volume,
#'   SoilMoisture_12cm.
#' @param date A \code{Date} object.
#' @param master_csv_path Character. Path to the master CSV.
#' @param replace Logical. If \code{TRUE}, removes any existing rows for this
#'   date before appending.
#' @return Invisible data frame of the appended rows (with Date column prepended).
append_to_master <- function(data, date, master_csv_path, replace = FALSE) {
  new_rows <- data.frame(
    Date             = format(date),
    Site             = data$Site,
    Subplot          = data$Subplot,
    SuctionRate      = data$SuctionRate,
    Time             = data$Time,
    Volume           = data$Volume,
    SoilMoisture_12cm = data$SoilMoisture_12cm,
    stringsAsFactors = FALSE
  )

  if (file.exists(master_csv_path)) {
    master <- utils::read.csv(master_csv_path, stringsAsFactors = FALSE)
    if (replace) master <- master[master$Date != format(date), ]
    combined <- rbind(master, new_rows)
  } else {
    combined <- new_rows
  }

  utils::write.csv(combined, master_csv_path, row.names = FALSE)
  invisible(new_rows)
}

#' Write one row to the append log (creates the log if it does not exist)
#'
#' @param append_log_path Character. Path to \code{outputs/infiltration_append_log.csv}.
#' @param filename Character. The daily entry filename just processed.
#' @param n_rows Integer. Number of rows appended.
#' @param date A \code{Date} object.
write_append_log <- function(append_log_path, filename, n_rows, date) {
  git_commit <- tryCatch(
    system("git rev-parse --short HEAD", intern = TRUE),
    error   = function(e) "unknown",
    warning = function(w) "unknown"
  )

  log_row <- data.frame(
    run_datetime_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    file_appended    = basename(filename),
    date_appended    = format(date),
    n_rows           = as.integer(n_rows),
    git_commit       = git_commit,
    stringsAsFactors = FALSE
  )

  log_dir <- dirname(append_log_path)
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  if (file.exists(append_log_path)) {
    existing <- utils::read.csv(append_log_path, stringsAsFactors = FALSE)
    utils::write.csv(rbind(existing, log_row), append_log_path, row.names = FALSE)
  } else {
    utils::write.csv(log_row, append_log_path, row.names = FALSE)
  }
  invisible(log_row)
}
