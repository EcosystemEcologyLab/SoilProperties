# soilmoisture_cleaning_functions.R
# Helper functions for clean_soilmoisture.R.
# Source soilmoisture_config.R before sourcing this file.

# ── Step 0: Filename parsing ───────────────────────────────────────────────────

#' Parse the field date from a daily entry filename
#'
#' @param filename Character. Bare filename or full path, e.g.
#'   \code{"B2_SoilMoisture_20260601.xlsx"}.
#' @return A \code{Date} object.
#' @examples
#' parse_date_from_filename("B2_SoilMoisture_20260601.xlsx")
parse_date_from_filename <- function(filename) {
  base <- basename(filename)
  m <- regmatches(base, regexpr("\\d{8}", base))
  if (length(m) == 0) {
    stop("Cannot parse 8-digit date from filename: ", base,
         "\nExpected format: B2_SoilMoisture_YYYYMMDD.xlsx")
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
#' @param filepath Character. Full path to the .xlsx file.
#' @return Named list with elements \code{sheet1} and \code{sheet2}, each a
#'   data frame with columns SoilType, PlantID, Sensor, Depth, Value.
read_entry_sheets <- function(filepath) {
  if (!file.exists(filepath)) {
    stop("File not found: ", filepath)
  }
  expected_cols <- c("SoilType", "PlantID", "Sensor", "Depth", "Value")

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
#' @param data Data frame with columns SoilType, PlantID, Sensor, Depth, Value.
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
    soil    <- data$SoilType[i]
    PlantID <- data$PlantID[i]
    sensor  <- data$Sensor[i]
    depth   <- data$Depth[i]
    value   <- data$Value[i]

    # ── Missing / blank ──────────────────────────────────────────────────────
    # Blank is UNKNOWN — never silently zeroed or dropped.
    if (is_blank(soil))    add(i, "SoilType: missing (blank/NA)",  soil)
    if (is_blank(PlantID)) add(i, "PlantID: missing (blank/NA)",   PlantID)
    if (is_blank(sensor))  add(i, "Sensor: missing (blank/NA)",    sensor)
    if (is_blank(depth))   add(i, "Depth: missing (blank/NA)",     depth)
    if (is_blank(value))   add(i, "Value: missing (blank/NA)",     value)

    soil_present    <- !is_blank(soil)
    PlantID_present <- !is_blank(PlantID)
    sensor_present  <- !is_blank(sensor)
    depth_present   <- !is_blank(depth)
    value_present   <- !is_blank(value)

    # ── SoilType ─────────────────────────────────────────────────────────────
    if (soil_present && !trimws(soil) %in% VALID_SOIL_TYPES) {
      add(i, paste0("SoilType: must be one of {",
                    paste(VALID_SOIL_TYPES, collapse = ", "), "}"), soil)
    }

    # ── PlantID ───────────────────────────────────────────────────────────────
    if (PlantID_present) {
      sp <- trimws(as.character(PlantID))
      if (nchar(sp) != 4 || !grepl("^[0-9]+$", sp))
        add(i, "PlantID: must be exactly 4 numbers", PlantID)
      } else if (!sp %in% VALID_PLANTID_CODES) {
        add(i, paste0("PlantID: '", sp, "' not in the allowed PlantID list"), PlantID)
      }
    }

    # ── Sensor ────────────────────────────────────────────────────────────────
    if (sensor_present && !trimws(sensor) %in% VALID_SENSORS) {
      add(i, "Sensor: must be T or M", sensor)
    }

    # ── Depth + Sensor ────────────────────────────────────────────────────────
    sensor_valid <- sensor_present && trimws(as.character(sensor)) %in% VALID_SENSORS
    if (sensor_valid && depth_present) {
      s <- trimws(as.character(sensor))
      d <- suppressWarnings(as.numeric(depth))
      if (is.na(d)) {
        add(i, "Depth: not numeric", depth)
      } else if (s == "M" && !d %in% DEPTH_M_VALID) {
        add(i, paste0("Depth: Sensor=M requires depth in {",
                      paste(DEPTH_M_VALID, collapse = ", "), "} cm"), depth)
      } else if (s == "T" && (d < DEPTH_T_MIN || d > DEPTH_T_MAX)) {
        add(i, paste0("Depth: Sensor=T requires ", DEPTH_T_MIN,
                      " – ", DEPTH_T_MAX, " cm"), depth)
      }
    }

    # ── Value + Sensor ────────────────────────────────────────────────────────
    if (sensor_valid && value_present) {
      s <- trimws(as.character(sensor))
      v <- suppressWarnings(as.numeric(value))
      if (is.na(v)) {
        add(i, "Value: not numeric", value)
      } else if (s == "M" && (v < VALUE_M_MIN || v > VALUE_M_MAX)) {
        add(i, paste0("Value: Sensor=M requires ", VALUE_M_MIN,
                      " – ", VALUE_M_MAX, " (% VWC)"), value)
      } else if (s == "T" && (v < VALUE_T_MIN || v > VALUE_T_MAX)) {
        add(i, paste0("Value: Sensor=T requires ", VALUE_T_MIN,
                      " – ", VALUE_T_MAX, " (°C)"), value)
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

#' Validate date and all rows, stopping loudly on any violation
#'
#' @param data Data frame with columns SoilType, PlantID, Sensor, Depth, Value.
#' @param date A \code{Date} object from the filename.
#' @return Invisible \code{data} when all rows pass.
validate_rows <- function(data, date) {
  date_viols <- validate_date(date)
  if (length(date_viols) > 0) {
    stop(
      "Date validation failed:\n  ", paste(date_viols, collapse = "\n  "),
      "\nFix the filename and re-run."
    )
  }

  viols <- detect_row_violations(data)
  if (nrow(viols) > 0) {
    message("Validation failed — ", nrow(viols), " violation(s):\n")
    print(viols, row.names = FALSE)
    stop(
      "\n", nrow(viols), " validation violation(s) found.\n",
      "Fix the source .xlsx and re-run."
    )
  }

  invisible(data)
}

# ── Step 3: Append to master ───────────────────────────────────────────────────

#' Check for an existing date in the master CSV and confirm replacement
#'
#' @param master_csv_path Character. Path to \code{B2_SoilMoisture_FullData.csv}.
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
#' @param data Data frame with columns SoilType, PlantID, Sensor, Depth, Value.
#' @param date A \code{Date} object.
#' @param master_csv_path Character. Path to the master CSV.
#' @param replace Logical. If \code{TRUE}, removes any existing rows for this
#'   date before appending.
#' @return Invisible data frame of the appended rows (with Date column).
append_to_master <- function(data, date, master_csv_path, replace = FALSE) {
  new_rows <- data.frame(
    Date     = format(date),
    SoilType = data$SoilType,
    PlantID  = data$PlantID,
    Sensor   = data$Sensor,
    Depth    = data$Depth,
    Value    = data$Value,
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
#' @param append_log_path Character. Path to \code{outputs/append_log.csv}.
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
