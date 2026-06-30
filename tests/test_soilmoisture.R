# tests/test_soilmoisture.R
# Run from the project root using either:
#   source("tests/test_soilmoisture.R")
#   testthat::test_file("tests/test_soilmoisture.R")
#
# Fixture file (tests/fixtures/B2_SoilMoisture_20260519.xlsx) is needed for the
# Step 1 and Step 2 fixture tests; all other tests use constructed data frames.

library(testthat)
library(openxlsx)

# Resolve the project root whether this file is sourced from the root or via
# testthat::test_file() (which changes working directory to tests/).
.proj_root <- if (file.exists("scripts/soilmoisture_config.R")) {
  "."
} else {
  ".."
}
source(file.path(.proj_root, "scripts", "soilmoisture_config.R"))
source(file.path(.proj_root, "scripts", "soilmoisture_cleaning_functions.R"))

FIXTURE <- file.path(.proj_root, "tests", "fixtures", "B2_SoilMoisture_20260519.xlsx")

# ── Helpers ────────────────────────────────────────────────────────────────────

# Returns a single-row data frame that passes all row-level validations.
valid_row <- function(SoilType = "PSAM", PlantID = "1234", Sensor = "M",
                      Depth = 12, Value = 15) {
  data.frame(SoilType = SoilType, PlantID = PlantID, Sensor = Sensor,
             Depth = Depth, Value = Value, stringsAsFactors = FALSE)
}

VALID_DATE <- as.Date("2026-06-01")  # within season, correct year

# ── parse_date_from_filename ───────────────────────────────────────────────────

test_that("parse_date_from_filename returns correct Date", {
  expect_equal(
    parse_date_from_filename("B2_SoilMoisture_20260601.xlsx"),
    as.Date("2026-06-01")
  )
})

test_that("parse_date_from_filename works with a full path", {
  expect_equal(
    parse_date_from_filename(file.path("some", "dir", "B2_SoilMoisture_20260715.xlsx")),
    as.Date("2026-07-15")
  )
})

test_that("parse_date_from_filename stops when no 8-digit run found", {
  expect_error(parse_date_from_filename("SoilMoisture.xlsx"), "Cannot parse")
})

# ── detect_sheet_mismatches ────────────────────────────────────────────────────

test_that("detect_sheet_mismatches returns zero rows for identical sheets", {
  s <- valid_row()
  result <- detect_sheet_mismatches(s, s)
  expect_equal(nrow(result), 0)
})

test_that("detect_sheet_mismatches classifies whitespace mismatch and quotes values", {
  s1 <- valid_row(Sensor = "M ")   # trailing space
  s2 <- valid_row(Sensor = "M")
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$mismatch_type, "whitespace")
  # Quoted output makes the space visible: '"M "' vs '"M"'
  expect_true(grepl('"M "', result$sheet1_value, fixed = TRUE))
  expect_true(grepl('"M"',  result$sheet2_value, fixed = TRUE))
})

test_that("detect_sheet_mismatches classifies case mismatch", {
  s1 <- valid_row(SoilType = "psam")
  s2 <- valid_row(SoilType = "PSAM")
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$mismatch_type, "case")
})

test_that("detect_sheet_mismatches classifies genuine value mismatch", {
  s1 <- valid_row(Value = 15)
  s2 <- valid_row(Value = 20)
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$mismatch_type, "value")
})

test_that("detect_sheet_mismatches reports the correct row and column", {
  s1 <- rbind(valid_row(), valid_row(Depth = 99))
  s2 <- rbind(valid_row(), valid_row(Depth = 20))
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(result$row, 2L)
  expect_equal(result$column, "Depth")
})

# ── compare_sheets ─────────────────────────────────────────────────────────────

test_that("compare_sheets stops on row count mismatch", {
  s1 <- rbind(valid_row(), valid_row())
  s2 <- valid_row()
  expect_error(compare_sheets(s1, s2), "Row count mismatch")
})

test_that("compare_sheets stops when a cell differs", {
  s1 <- valid_row(Value = 15)
  s2 <- valid_row(Value = 20)
  expect_error(compare_sheets(s1, s2))
})

test_that("compare_sheets returns sheet1 invisibly when sheets agree", {
  s <- valid_row()
  result <- compare_sheets(s, s)
  expect_equal(result, s)
})

# ── validate_date ──────────────────────────────────────────────────────────────

test_that("validate_date passes a valid in-season date", {
  expect_length(validate_date(as.Date("2026-06-15")), 0)
})

test_that("validate_date fails for wrong year", {
  v <- validate_date(as.Date("2025-06-15"))
  expect_true(any(grepl("Year", v)))
})

test_that("validate_date fails for a date before SEASON_START", {
  v <- validate_date(as.Date("2026-05-01"))
  expect_true(any(grepl("season window", v)))
})

test_that("validate_date fails for a date after SEASON_END", {
  v <- validate_date(as.Date("2026-10-01"))
  expect_true(any(grepl("season window", v)))
})

test_that("validate_date passes on the season boundary dates", {
  expect_length(validate_date(SEASON_START), 0)
  expect_length(validate_date(SEASON_END),   0)
})

# ── detect_row_violations ──────────────────────────────────────────────────────

test_that("detect_row_violations passes a fully valid row", {
  expect_equal(nrow(detect_row_violations(valid_row())), 0)
})

test_that("detect_row_violations catches invalid SoilType", {
  v <- detect_row_violations(valid_row(SoilType = "XXXX"))
  expect_true(any(grepl("SoilType.*must be one of", v$rule)))
})

test_that("detect_row_violations catches missing SoilType (NA)", {
  v <- detect_row_violations(valid_row(SoilType = NA))
  expect_true(any(grepl("SoilType.*missing", v$rule)))
})

test_that("detect_row_violations catches missing SoilType (blank string)", {
  v <- detect_row_violations(valid_row(SoilType = ""))
  expect_true(any(grepl("SoilType.*missing", v$rule)))
})

test_that("detect_row_violations catches PlantID of wrong length", {
  v <- detect_row_violations(valid_row(PlantID = "12345"))  # 5 digits
  expect_true(any(grepl("PlantID.*4 numeric digits", v$rule)))
})

test_that("detect_row_violations catches PlantID with non-numeric characters", {
  v <- detect_row_violations(valid_row(PlantID = "12ab"))  # letters in it
  expect_true(any(grepl("PlantID.*4 numeric digits", v$rule)))
})

test_that("detect_row_violations catches PlantID that is all letters", {
  v <- detect_row_violations(valid_row(PlantID = "abcd"))  # no digits
  expect_true(any(grepl("PlantID.*4 numeric digits", v$rule)))
})

test_that("detect_row_violations accepts PlantID with leading zeros", {
  # "0042" must stay 4 chars — leading zero preserved when read as character
  expect_equal(nrow(detect_row_violations(valid_row(PlantID = "0042"))), 0)
})

test_that("detect_row_violations rejects PlantID missing leading zero (3 chars)", {
  v <- detect_row_violations(valid_row(PlantID = "042"))  # would result from numeric coercion
  expect_true(any(grepl("PlantID.*4 numeric digits", v$rule)))
})

test_that("detect_row_violations catches invalid Sensor", {
  v <- detect_row_violations(valid_row(Sensor = "X"))
  expect_true(any(grepl("Sensor.*must be T or M", v$rule)))
})

test_that("detect_row_violations catches wrong depth for Sensor=M (depth 5)", {
  v <- detect_row_violations(valid_row(Sensor = "M", Depth = 5, Value = 15))
  expect_true(any(grepl("Depth.*Sensor=M", v$rule)))
})

test_that("detect_row_violations accepts both valid depths for Sensor=M", {
  expect_equal(nrow(detect_row_violations(valid_row(Sensor = "M", Depth = 12, Value = 15))), 0)
  expect_equal(nrow(detect_row_violations(valid_row(Sensor = "M", Depth = 20, Value = 15))), 0)
})

test_that("detect_row_violations catches depth > DEPTH_T_MAX for Sensor=T", {
  v <- detect_row_violations(valid_row(Sensor = "T", Depth = 90, Value = 25))
  expect_true(any(grepl("Depth.*Sensor=T", v$rule)))
})

test_that("detect_row_violations catches depth = 0 for Sensor=T", {
  v <- detect_row_violations(valid_row(Sensor = "T", Depth = 0, Value = 25))
  expect_true(any(grepl("Depth.*Sensor=T", v$rule)))
})

test_that("detect_row_violations catches Value > VALUE_M_MAX for Sensor=M", {
  v <- detect_row_violations(valid_row(Sensor = "M", Depth = 12, Value = 50))
  expect_true(any(grepl("Value.*Sensor=M", v$rule)))
})

test_that("detect_row_violations catches Value < VALUE_M_MIN for Sensor=M", {
  v <- detect_row_violations(valid_row(Sensor = "M", Depth = 12, Value = -1))
  expect_true(any(grepl("Value.*Sensor=M", v$rule)))
})

test_that("detect_row_violations catches Value < VALUE_T_MIN for Sensor=T", {
  v <- detect_row_violations(valid_row(Sensor = "T", Depth = 10, Value = 5))
  expect_true(any(grepl("Value.*Sensor=T", v$rule)))
})

test_that("detect_row_violations catches Value > VALUE_T_MAX for Sensor=T", {
  v <- detect_row_violations(valid_row(Sensor = "T", Depth = 10, Value = 60))
  expect_true(any(grepl("Value.*Sensor=T", v$rule)))
})

test_that("detect_row_violations reports all violations in a row, not just the first", {
  bad <- valid_row(SoilType = "XXXX", PlantID = "Bad!", Sensor = "X")
  v <- detect_row_violations(bad)
  # At least 3 violations from 3 bad fields
  expect_gte(nrow(v), 3L)
  expect_true(all(v$row == 1L))
})

# ── check_duplicate_date ───────────────────────────────────────────────────────

test_that("check_duplicate_date returns FALSE when master does not exist", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  expect_false(check_duplicate_date(tmp, VALID_DATE))
})

test_that("check_duplicate_date returns FALSE when date is not in master", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  utils::write.csv(
    data.frame(Date = "2026-06-01", SoilType = "PSAM", PlantID = "1234",
               Sensor = "M", Depth = 12, Value = 15),
    tmp, row.names = FALSE
  )
  expect_false(check_duplicate_date(tmp, as.Date("2026-07-01")))
})

test_that("check_duplicate_date returns TRUE when date exists and user says Y", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  utils::write.csv(
    data.frame(Date = format(VALID_DATE), SoilType = "PSAM", PlantID = "1234",
               Sensor = "M", Depth = 12, Value = 15),
    tmp, row.names = FALSE
  )
  result <- check_duplicate_date(tmp, VALID_DATE, confirm_fn = function(...) "Y")
  expect_true(result)
})

test_that("check_duplicate_date stops when date exists and user says N", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  utils::write.csv(
    data.frame(Date = format(VALID_DATE), SoilType = "PSAM", PlantID = "1234",
               Sensor = "M", Depth = 12, Value = 15),
    tmp, row.names = FALSE
  )
  expect_error(
    check_duplicate_date(tmp, VALID_DATE, confirm_fn = function(...) "N"),
    "Append cancelled"
  )
})

# ── append_to_master ───────────────────────────────────────────────────────────

test_that("append_to_master creates master CSV if it does not exist", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  append_to_master(valid_row(), VALID_DATE, tmp)
  result <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(result), 1L)
  expect_equal(result$Date[1], format(VALID_DATE))
})

test_that("append_to_master appends new date without touching existing rows", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  append_to_master(valid_row(), as.Date("2026-06-01"), tmp)
  append_to_master(valid_row(), as.Date("2026-06-02"), tmp)
  result <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(result), 2L)
  expect_equal(sort(result$Date), c("2026-06-01", "2026-06-02"))
})

test_that("append_to_master with replace=TRUE removes old rows for that date only", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  # Write two dates
  append_to_master(valid_row(Value = 10), as.Date("2026-06-01"), tmp)
  append_to_master(valid_row(Value = 20), as.Date("2026-06-02"), tmp)
  # Replace June 1 with a new value
  append_to_master(valid_row(Value = 99), as.Date("2026-06-01"), tmp, replace = TRUE)
  result <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  # Still 2 rows total
  expect_equal(nrow(result), 2L)
  # June 1 now has Value 99
  expect_equal(result$Value[result$Date == "2026-06-01"], 99)
  # June 2 is untouched
  expect_equal(result$Value[result$Date == "2026-06-02"], 20)
})

# ── Fixture-based tests ────────────────────────────────────────────────────────
# tests/fixtures/B2_SoilMoisture_20260519.xlsx uses the OLD column layout:
# columns are SoilType, Species, Sensor, Depth, Value (no PlantID column).
# Tests that required successfully reading through read_entry_sheets() have been
# removed — this fixture now needs to be rebuilt with PlantID before those
# row-content tests can be restored. The date and duplicate-check tests below
# do not rely on read_entry_sheets() and remain valid.

test_that("Step 1 fixture: read_entry_sheets stops — fixture uses old Species column (PlantID missing)", {
  skip_if_not(file.exists(FIXTURE), "fixture file not present — copy it to tests/fixtures/")
  expect_error(
    read_entry_sheets(FIXTURE),
    "missing expected column"
  )
})

test_that("Step 2 fixture: date 2026-05-19 fails season-window check", {
  skip_if_not(file.exists(FIXTURE), "fixture file not present — copy it to tests/fixtures/")
  fixture_date <- parse_date_from_filename(FIXTURE)
  viols <- validate_date(fixture_date)
  expect_true(any(grepl("season window", viols)))
})

test_that("Step 3 fixture: second append of same date is refused", {
  skip_if_not(file.exists(FIXTURE), "fixture file not present — copy it to tests/fixtures/")
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  fixture_date <- parse_date_from_filename(FIXTURE)
  utils::write.csv(
    data.frame(Date = format(fixture_date), SoilType = "PSAM", PlantID = "1234",
               Sensor = "M", Depth = 12, Value = 15),
    tmp, row.names = FALSE
  )
  expect_error(
    check_duplicate_date(tmp, fixture_date, confirm_fn = function(...) "N"),
    "Append cancelled"
  )
})
