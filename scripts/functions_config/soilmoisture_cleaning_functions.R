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
    df <- df[, expected_cols]
    # Guard against leading-zero loss: if openxlsx coerced PlantID from a
    # number-formatted cell (e.g. "0042" → 42), restore the 4-char zero-padded
    # string. Text-formatted cells arrive as character and are left unchanged.
    if (is.numeric(df$PlantID)) {
      df$PlantID <- formatC(df$PlantID, width = 4, flag = "0", format = "d")
    } else {
      df$PlantID <- as.character(df$PlantID)
    }
    df
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
#' Checks categorical and range rules only (Tier 3). Blank or NA cells are
#' unknown data and pass through without flagging (Tier 2 — no missing-value
#' violations). Out-of-range numeric values, unrecognised SoilType, unrecognised
#' Sensor, wrong Depth for sensor type, and non-numeric where numeric is expected
#' are all reported.
#'
#' @param data Data frame with columns SoilType, PlantID, Sensor, Depth, Value.
#' @return Data frame with columns \code{row}, \code{column}, \code{rule},
#'   \code{observed_value}. Zero rows means all rows pass.
detect_row_violations <- function(data) {
  violations <- list()

  add <- function(row, column, rule, val) {
    violations[[length(violations) + 1]] <<- data.frame(
      row            = row,
      column         = column,
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

    # ── SoilType ─────────────────────────────────────────────────────────────
    if (!is_blank(soil) && !trimws(soil) %in% VALID_SOIL_TYPES) {
      add(i, "SoilType",
          paste0("SoilType: must be one of {", paste(VALID_SOIL_TYPES, collapse = ", "), "}"),
          soil)
    }

    # ── PlantID ───────────────────────────────────────────────────────────────
    if (!is_blank(PlantID)) {
      sp <- trimws(as.character(PlantID))
      if (nchar(sp) != 4 || !grepl("^[0-9]+$", sp)) {
        add(i, "PlantID", "PlantID: must be exactly 4 numeric digits", PlantID)
      }
    }

    # ── Sensor ────────────────────────────────────────────────────────────────
    if (!is_blank(sensor) && !trimws(sensor) %in% VALID_SENSORS) {
      add(i, "Sensor", "Sensor: must be T or M", sensor)
    }

    # ── Depth + Sensor ────────────────────────────────────────────────────────
    sensor_valid <- !is_blank(sensor) && trimws(as.character(sensor)) %in% VALID_SENSORS
    if (sensor_valid && !is_blank(depth)) {
      s <- trimws(as.character(sensor))
      d <- suppressWarnings(as.numeric(depth))
      if (is.na(d)) {
        add(i, "Depth", "Depth: not numeric", depth)
      } else if (s == "M" && !d %in% DEPTH_M_VALID) {
        add(i, "Depth",
            paste0("Depth: Sensor=M requires depth in {",
                   paste(DEPTH_M_VALID, collapse = ", "), "} cm"),
            depth)
      } else if (s == "T" && (d < DEPTH_T_MIN || d > DEPTH_T_MAX)) {
        add(i, "Depth",
            paste0("Depth: Sensor=T requires ", DEPTH_T_MIN, " – ", DEPTH_T_MAX, " cm"),
            depth)
      }
    }

    # ── Value + Sensor ────────────────────────────────────────────────────────
    if (sensor_valid && !is_blank(value)) {
      s <- trimws(as.character(sensor))
      v <- suppressWarnings(as.numeric(value))
      if (is.na(v)) {
        add(i, "Value", "Value: not numeric", value)
      } else if (s == "M" && (v < VALUE_M_MIN || v > VALUE_M_MAX)) {
        add(i, "Value",
            paste0("Value: Sensor=M requires ", VALUE_M_MIN,
                   " – ", VALUE_M_MAX, " (% VWC)"),
            value)
      } else if (s == "T" && (v < VALUE_T_MIN || v > VALUE_T_MAX)) {
        add(i, "Value",
            paste0("Value: Sensor=T requires ", VALUE_T_MIN,
                   " – ", VALUE_T_MAX, " (°C)"),
            value)
      }
    }
  }

  if (length(violations) == 0) {
    return(data.frame(
      row = integer(0), column = character(0),
      rule = character(0), observed_value = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, violations)
}

#' Write a corrected value back to both sheets of the source xlsx
#'
#' @param filepath Character. Full path to the .xlsx file.
#' @param row_idx Integer. 1-based data row index (not counting the header row).
#' @param col_name Character. Column name to update.
#' @param new_value The replacement value (typed to match the column).
write_correction_to_xlsx <- function(filepath, row_idx, col_name, new_value) {
  wb <- tryCatch(
    openxlsx::loadWorkbook(filepath),
    error = function(e) stop(
      "Cannot open workbook for writing: ", filepath, "\n",
      conditionMessage(e), call. = FALSE
    )
  )
  s1_names <- names(openxlsx::read.xlsx(wb, sheet = 1))
  s2_names <- names(openxlsx::read.xlsx(wb, sheet = 2))
  col1 <- which(s1_names == col_name)
  col2 <- which(s2_names == col_name)
  if (length(col1) == 0) stop("Column '", col_name, "' not found in Sheet1.", call. = FALSE)
  if (length(col2) == 0) stop("Column '", col_name, "' not found in Sheet2.", call. = FALSE)
  # row_idx is the 1-based data row; +1 accounts for the header row in xlsx
  openxlsx::writeData(wb, sheet = 1, x = new_value,
                      startRow = row_idx + 1L, startCol = col1[1])
  openxlsx::writeData(wb, sheet = 2, x = new_value,
                      startRow = row_idx + 1L, startCol = col2[1])
  tryCatch(
    openxlsx::saveWorkbook(wb, filepath, overwrite = TRUE),
    error = function(e) stop(
      "Failed to save workbook: ", filepath, "\n",
      "Attempted to set row ", row_idx, ", column '", col_name,
      "' to '", new_value, "'.\n",
      "Save the value manually in both sheets and re-run.\n",
      conditionMessage(e), call. = FALSE
    )
  )
  invisible(TRUE)
}

#' Interactively review violations with the user
#'
#' Prints the full violations table, then loops through each violation one at a
#' time, prompting the user to enter a corrected value or press Y to flag the
#' row. Corrections are validated against the same rule before being written back
#' to both sheets of the source xlsx. Invalid corrections are re-prompted.
#'
#' @param data Data frame with columns SoilType, PlantID, Sensor, Depth, Value.
#' @param viols Data frame returned by \code{detect_row_violations}.
#' @param filepath Character. Full path to the source .xlsx (for write-back).
#' @param confirm_fn Function used to prompt the user; defaults to
#'   \code{readline}. Override in tests to avoid interactive blocking.
#' @param write_fn Function used to write back to xlsx; defaults to
#'   \code{write_correction_to_xlsx}. Override in tests.
#' @return \code{data} with a \code{Flag} column: \code{"REVIEW"} for rows the
#'   user flagged with Y, \code{NA} for all others.
review_violations <- function(data, viols, filepath,
                              confirm_fn = readline,
                              write_fn   = write_correction_to_xlsx) {
  data$Flag <- NA_character_

  cat(paste0(
    "\n── Validation violations ─────────────────────────────────────────\n",
    nrow(viols), " violation(s) across ",
    length(unique(viols$row)), " row(s):\n\n"
  ))
  print(viols, row.names = FALSE)
  cat("\n")

  for (k in seq_len(nrow(viols))) {
    v        <- viols[k, ]
    row_idx  <- v$row
    col_name <- v$column
    obs_val  <- v$observed_value
    rule_txt <- v$rule

    repeat {
      answer <- trimws(confirm_fn(paste0(
        "\nRow ", row_idx, " | ", col_name,
        " | Sensor=", data$Sensor[row_idx],
        " | observed: ", obs_val,
        " | rule: ", rule_txt,
        "\n  Enter a corrected value, or press Y to flag this row and keep the original value: "
      )))

      if (toupper(answer) == "Y") {
        data$Flag[row_idx] <- "REVIEW"
        message("  Row ", row_idx, " flagged as REVIEW.")
        break
      }

      # Validate the candidate correction against the same rule
      test_row             <- data[row_idx, , drop = FALSE]
      test_row[[col_name]] <- answer
      new_viols  <- detect_row_violations(test_row)
      still_bad  <- new_viols[!is.na(new_viols$column) & new_viols$column == col_name, ]

      if (nrow(still_bad) == 0) {
        typed_val    <- if (is.numeric(data[[col_name]])) {
          suppressWarnings(as.numeric(answer))
        } else {
          answer
        }
        original_val <- data[[col_name]][row_idx]
        write_fn(filepath, row_idx, col_name, typed_val)
        data[[col_name]][row_idx] <- typed_val
        message("  Row ", row_idx, " '", col_name, "' corrected: '",
                original_val, "' → '", typed_val, "'.")
        break
      } else {
        cat("  '", answer, "' still fails: ", still_bad$rule[1],
            " — try again.\n", sep = "")
      }
    }
  }

  data
}

#' Validate the date, stopping loudly on any violation
#'
#' Row-level range and categorical checks are now handled interactively by
#' \code{review_violations} in the pipeline script. This function only enforces
#' the date check (wrong year, outside season window).
#'
#' @param data Data frame (passed through unchanged).
#' @param date A \code{Date} object from the filename.
#' @return Invisible \code{data} when the date is valid.
validate_rows <- function(data, date) {
  date_viols <- validate_date(date)
  if (length(date_viols) > 0) {
    stop(
      "Date validation failed:\n  ", paste(date_viols, collapse = "\n  "),
      "\nFix the filename and re-run."
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

  master <- utils::read.csv(master_csv_path, stringsAsFactors = FALSE,
                             colClasses = c(PlantID = "character"))
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
#' @param data Data frame with columns SoilType, PlantID, Sensor, Depth, Value,
#'   and optionally Flag. If Flag is absent it is set to \code{NA} for all rows.
#' @param date A \code{Date} object.
#' @param master_csv_path Character. Path to the master CSV.
#' @param replace Logical. If \code{TRUE}, removes any existing rows for this
#'   date before appending.
#' @return Invisible data frame of the appended rows (with Date and Flag columns).
append_to_master <- function(data, date, master_csv_path, replace = FALSE) {
  if (!"Flag" %in% names(data)) data$Flag <- NA_character_

  new_rows <- data.frame(
    Date     = format(date),
    SoilType = data$SoilType,
    PlantID  = data$PlantID,
    Sensor   = data$Sensor,
    Depth    = data$Depth,
    Value    = data$Value,
    Flag     = data$Flag,
    stringsAsFactors = FALSE
  )

  if (file.exists(master_csv_path)) {
    master <- utils::read.csv(master_csv_path, stringsAsFactors = FALSE,
                              colClasses = c(PlantID = "character"))
    if (!"Flag" %in% names(master)) master$Flag <- NA_character_
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
