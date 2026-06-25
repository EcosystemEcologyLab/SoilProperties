# Tests for R/soilinfiltration_cleaning_functions.R.
#
# Contract: stop-loudly at the first failing step. Tests verify that:
#   - violations produce stop() with an informative message
#   - clean data passes through invisibly
#   - the fixture file (Soil_Infiltration_FieldData_20260528.xlsx) triggers
#     the known structural violation (Sheet1 missing SoilType, Group, and
#     SoilMoisture_12cm; Sheet2 missing SoilType and Group)
#
# helper-root.R sets the working directory to PROJECT_ROOT and exposes
# PROJECT_ROOT. We source the infiltration config and cleaning functions here
# (not in the helper) to keep the infiltration and moisture test namespaces
# cleanly separated.

setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "R", "soilinfiltration_config.R"))
source(file.path(PROJECT_ROOT, "R", "soilinfiltration_cleaning_functions.R"))

FIXTURE <- file.path(PROJECT_ROOT, "tests", "fixtures",
                     "Soil_Infiltration_FieldData_20260528.xlsx")

VALID_DATE <- as.Date("2026-06-01")   # in-season, correct year

# ── Helpers ────────────────────────────────────────────────────────────────────

# Returns a single-row data frame that passes all row-level validations.
valid_row <- function(SoilType = "PSAM", Group = "1", SuctionRate = 2,
                      Time = 0, Volume = 90, SoilMoisture_12cm = 8.5) {
  data.frame(SoilType = SoilType, Group = Group, SuctionRate = SuctionRate,
             Time = Time, Volume = Volume, SoilMoisture_12cm = SoilMoisture_12cm,
             stringsAsFactors = FALSE)
}

# Returns a tidy replicate (6 rows, t=0 anchor, monotonic time/volume,
# constant suction) that passes all replicate-level checks.
valid_replicate <- function(soiltype = "PSAM", group = "1", suction = 2) {
  data.frame(
    SoilType          = soiltype,
    Group             = group,
    SuctionRate       = suction,
    Time              = c(0,  30,  60,  90, 120, 150),
    Volume            = c(90, 86,  82,  79,  76,  73),
    SoilMoisture_12cm = 8.5,
    stringsAsFactors  = FALSE
  )
}

# ── parse_date_from_filename ───────────────────────────────────────────────────

test_that("parse_date_from_filename returns correct Date for valid filename", {
  expect_equal(
    parse_date_from_filename("Soil_Infiltration_FieldData_20260601.xlsx"),
    as.Date("2026-06-01")
  )
})

test_that("parse_date_from_filename works with a full path", {
  expect_equal(
    parse_date_from_filename(
      file.path("some", "dir", "Soil_Infiltration_FieldData_20260715.xlsx")
    ),
    as.Date("2026-07-15")
  )
})

test_that("parse_date_from_filename stops when no 8-digit run found", {
  expect_error(
    parse_date_from_filename("SoilInfiltration.xlsx"),
    "Cannot parse"
  )
})

test_that("parse_date_from_filename stops for an invalid calendar date", {
  expect_error(
    parse_date_from_filename("Soil_Infiltration_FieldData_20260230.xlsx"),
    "not a valid calendar date"
  )
})

# ── detect_sheet_mismatches ────────────────────────────────────────────────────

test_that("detect_sheet_mismatches returns zero rows for identical sheets", {
  s <- valid_row()
  expect_equal(nrow(detect_sheet_mismatches(s, s)), 0)
})

test_that("detect_sheet_mismatches classifies whitespace mismatch and quotes values", {
  s1 <- valid_row(SoilType = "PSAM ")   # trailing space
  s2 <- valid_row(SoilType = "PSAM")
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$mismatch_type, "whitespace")
  expect_true(grepl('"PSAM "', result$sheet1_value, fixed = TRUE))
})

test_that("detect_sheet_mismatches classifies case mismatch", {
  s1 <- valid_row(SoilType = "psam")
  s2 <- valid_row(SoilType = "PSAM")
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$mismatch_type, "case")
})

test_that("detect_sheet_mismatches classifies genuine value mismatch", {
  s1 <- valid_row(Volume = 88)
  s2 <- valid_row(Volume = 90)
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$mismatch_type, "value")
})

test_that("detect_sheet_mismatches reports the correct row and column", {
  s1 <- rbind(valid_row(), valid_row(SuctionRate = 3))
  s2 <- rbind(valid_row(), valid_row(SuctionRate = 5))
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(result$row, 2L)
  expect_equal(result$column, "SuctionRate")
})

test_that("detect_sheet_mismatches includes SoilMoisture_12cm in comparison", {
  s1 <- valid_row(SoilMoisture_12cm = 8.5)
  s2 <- valid_row(SoilMoisture_12cm = 9.1)
  result <- detect_sheet_mismatches(s1, s2)
  expect_equal(nrow(result), 1)
  expect_equal(result$column, "SoilMoisture_12cm")
})

# ── compare_sheets ─────────────────────────────────────────────────────────────

test_that("compare_sheets stops on row count mismatch", {
  s1 <- rbind(valid_row(), valid_row())
  s2 <- valid_row()
  expect_error(compare_sheets(s1, s2), "Row count mismatch")
})

test_that("compare_sheets stops when a cell differs", {
  s1 <- valid_row(Volume = 88)
  s2 <- valid_row(Volume = 90)
  expect_error(compare_sheets(s1, s2))
})

test_that("compare_sheets returns sheet1 invisibly when sheets agree", {
  s <- valid_row()
  expect_equal(compare_sheets(s, s), s)
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

test_that("detect_row_violations catches missing SoilType (NA)", {
  v <- detect_row_violations(valid_row(SoilType = NA))
  expect_true(any(grepl("SoilType.*missing", v$rule)))
})

test_that("detect_row_violations catches missing Group (blank string)", {
  v <- detect_row_violations(valid_row(Group = ""))
  expect_true(any(grepl("Group.*missing", v$rule)))
})

test_that("detect_row_violations catches invalid SoilType", {
  v <- detect_row_violations(valid_row(SoilType = "XXXX"))
  expect_true(any(grepl("SoilType.*must be one of", v$rule)))
})

test_that("detect_row_violations catches missing SuctionRate", {
  v <- detect_row_violations(valid_row(SuctionRate = NA))
  expect_true(any(grepl("SuctionRate.*missing", v$rule)))
})

test_that("detect_row_violations catches non-numeric SuctionRate", {
  v <- detect_row_violations(valid_row(SuctionRate = "fast"))
  expect_true(any(grepl("SuctionRate.*not numeric", v$rule)))
})

test_that("detect_row_violations catches SuctionRate not in allowed set", {
  v <- detect_row_violations(valid_row(SuctionRate = 8))
  expect_true(any(grepl("SuctionRate.*must be one of", v$rule)))
})

test_that("detect_row_violations accepts all 8 valid suction rates", {
  for (s in VALID_SUCTIONS_CM) {
    expect_equal(nrow(detect_row_violations(valid_row(SuctionRate = s))), 0,
                 info = paste("suction =", s))
  }
})

test_that("detect_row_violations catches negative Time", {
  v <- detect_row_violations(valid_row(Time = -10))
  expect_true(any(grepl("Time.*negative", v$rule)))
})

test_that("detect_row_violations catches Time exceeding TIME_MAX_S", {
  v <- detect_row_violations(valid_row(Time = TIME_MAX_S + 1))
  expect_true(any(grepl("Time.*TIME_MAX_S", v$rule)))
})

test_that("detect_row_violations catches negative Volume", {
  v <- detect_row_violations(valid_row(Volume = -1))
  expect_true(any(grepl("Volume.*negative", v$rule)))
})

test_that("detect_row_violations catches Volume exceeding MAX_VOLUME_ML", {
  v <- detect_row_violations(valid_row(Volume = MAX_VOLUME_ML + 1))
  expect_true(any(grepl("Volume.*MAX_VOLUME_ML", v$rule)))
})

test_that("detect_row_violations: SoilMoisture_12cm with garbage values produces zero violations", {
  # Reference column — no checks applied regardless of value.
  v <- detect_row_violations(valid_row(SoilMoisture_12cm = "GARBAGE"))
  expect_equal(nrow(v), 0)
  v2 <- detect_row_violations(valid_row(SoilMoisture_12cm = -9999))
  expect_equal(nrow(v2), 0)
})

test_that("detect_row_violations reports all violations in a row, not just the first", {
  bad <- valid_row(SoilType = "XXXX", SuctionRate = 99, Volume = -5)
  v   <- detect_row_violations(bad)
  expect_gte(nrow(v), 3L)
  expect_true(all(v$row == 1L))
})

# ── detect_replicate_violations ────────────────────────────────────────────────

test_that("detect_replicate_violations passes a clean replicate", {
  expect_equal(nrow(detect_replicate_violations(valid_replicate())), 0)
})

test_that("detect_replicate_violations catches missing t=0 anchor", {
  d <- valid_replicate()
  d$Time <- c(10, 30, 60, 90, 120, 150)   # no t=0
  v <- detect_replicate_violations(d)
  expect_true(any(grepl("missing t=0 anchor", v$rule)))
})

test_that("detect_replicate_violations catches duplicate t=0 anchor", {
  d <- valid_replicate()
  d$Time[2] <- 0   # two zeros
  v <- detect_replicate_violations(d)
  expect_true(any(grepl("duplicate t=0 anchor", v$rule)))
})

test_that("detect_replicate_violations catches non-monotonic Time", {
  d <- valid_replicate()
  d$Time <- c(0, 30, 60, 40, 120, 150)   # row 4 steps back
  v <- detect_replicate_violations(d)
  expect_true(any(grepl("non-monotonic Time", v$rule)))
})

test_that("detect_replicate_violations catches Volume rise > VOL_MONOTONIC_TOLERANCE_ML", {
  d <- valid_replicate()
  d$Volume <- c(90, 85, 88, 79, 76, 73)   # row 3: 85->88, rise of 3 mL
  v <- detect_replicate_violations(d)
  expect_true(any(grepl("non-monotonic Volume", v$rule)))
})

test_that("detect_replicate_violations passes Volume rise <= VOL_MONOTONIC_TOLERANCE_ML (0.5 mL)", {
  d <- valid_replicate()
  d$Volume <- c(90, 85, 85.5, 82, 79, 77)   # rise of 0.5 mL — within tolerance
  expect_equal(nrow(detect_replicate_violations(d)), 0)
})

test_that("detect_replicate_violations catches inconsistent SuctionRate within replicate", {
  d <- valid_replicate()
  d$SuctionRate[4] <- 3   # one row has a different suction
  v <- detect_replicate_violations(d)
  expect_true(any(grepl("SuctionRate inconsistent", v$rule)))
})

test_that("detect_replicate_violations handles two replicates independently", {
  r1 <- valid_replicate(soiltype = "PSAM")
  r2 <- valid_replicate(soiltype = "THCL")
  r2$Time <- c(10, 30, 60, 90, 120, 150)   # r2 missing t=0
  combined <- rbind(r1, r2)
  v <- detect_replicate_violations(combined)
  # Only r2 should flag
  expect_true(any(grepl("missing t=0", v$rule)))
  expect_false(any(grepl("PSAM", v$rule)))   # r1 clean
  expect_true( any(grepl("THCL", v$rule)))   # r2 flagged
})

# ── validate_rows ──────────────────────────────────────────────────────────────

test_that("validate_rows returns data invisibly for clean input", {
  d <- valid_replicate()
  expect_equal(validate_rows(d, VALID_DATE), d)
})

test_that("validate_rows stops on date violation", {
  d <- valid_replicate()
  expect_error(validate_rows(d, as.Date("2025-06-01")), "Date validation failed")
})

test_that("validate_rows stops and emits message on row violation", {
  d <- valid_replicate()
  d$SoilType[2] <- "XXXX"
  # message() is called before stop(), so expect_message captures it;
  # the stop() propagates as an error which expect_error catches separately.
  expect_message(
    tryCatch(validate_rows(d, VALID_DATE), error = function(e) NULL),
    "Validation failed"
  )
  expect_error(validate_rows(d, VALID_DATE), "validation violation")
})

test_that("validate_rows stops and emits message on replicate violation", {
  d <- valid_replicate()
  d$Time[2] <- 0   # duplicate t=0
  expect_message(
    tryCatch(validate_rows(d, VALID_DATE), error = function(e) NULL),
    "Replicate validation failed"
  )
  expect_error(validate_rows(d, VALID_DATE), "replicate violation")
})

test_that("validate_rows short-circuits: replicate checks not run when row violations exist", {
  # Both a row violation (bad SoilType) and a replicate violation (no t=0)
  # are present. Only the row violation message should appear.
  d <- valid_replicate()
  d$SoilType <- "XXXX"
  d$Time     <- c(10, 30, 60, 90, 120, 150)   # also missing t=0
  err <- tryCatch(validate_rows(d, VALID_DATE), error = function(e) e$message)
  expect_true(grepl("validation violation", err))
  expect_false(grepl("replicate", err))
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
    data.frame(Date = "2026-06-01", SoilType = "PSAM", Group = "1",
               SuctionRate = 2, Time = 0, Volume = 90, SoilMoisture_12cm = 8.5),
    tmp, row.names = FALSE
  )
  expect_false(check_duplicate_date(tmp, as.Date("2026-07-01")))
})

test_that("check_duplicate_date returns TRUE when date exists and user says Y", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  utils::write.csv(
    data.frame(Date = format(VALID_DATE), SoilType = "PSAM", Group = "1",
               SuctionRate = 2, Time = 0, Volume = 90, SoilMoisture_12cm = 8.5),
    tmp, row.names = FALSE
  )
  expect_true(check_duplicate_date(tmp, VALID_DATE, confirm_fn = function(...) "Y"))
})

test_that("check_duplicate_date stops when date exists and user says N", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  utils::write.csv(
    data.frame(Date = format(VALID_DATE), SoilType = "PSAM", Group = "1",
               SuctionRate = 2, Time = 0, Volume = 90, SoilMoisture_12cm = 8.5),
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
  append_to_master(valid_replicate(), VALID_DATE, "test.xlsx", tmp)
  result <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(result), nrow(valid_replicate()))
  expect_equal(result$Date[1], format(VALID_DATE))
})

test_that("append_to_master appends new date without touching existing rows", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  append_to_master(valid_replicate(), as.Date("2026-06-01"), "test.xlsx", tmp)
  append_to_master(valid_replicate(), as.Date("2026-06-02"), "test.xlsx", tmp)
  result <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(result), 2 * nrow(valid_replicate()))
  expect_equal(sort(unique(result$Date)), c("2026-06-01", "2026-06-02"))
})

test_that("append_to_master with replace=TRUE removes old rows for that date only", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  r1 <- valid_replicate(); r1$Volume <- 80
  r2 <- valid_replicate(); r2$Volume <- 70
  append_to_master(r1, as.Date("2026-06-01"), "test.xlsx", tmp)
  append_to_master(r2, as.Date("2026-06-02"), "test.xlsx", tmp)
  r3 <- valid_replicate(); r3$Volume <- 99
  append_to_master(r3, as.Date("2026-06-01"), "test.xlsx", tmp, replace = TRUE)
  result <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(result), 2 * nrow(valid_replicate()))
  expect_equal(result$Volume[result$Date == "2026-06-01"][1], 99)
  expect_equal(result$Volume[result$Date == "2026-06-02"][1], 70)
})

# ── Fixture-based tests ────────────────────────────────────────────────────────
# Soil_Infiltration_FieldData_20260528.xlsx has the OLD column layout and known
# structural issues:
#   Sheet1 columns: Site, Subplot, SuctionRate, Time, Volume
#     → missing SoilType, Group, SoilMoisture_12cm (all three required)
#   Sheet2 columns: Site, Subplot, SuctionRate, Time, Volume, SoilMoisture_12cm
#     → missing SoilType and Group
#
#   read_entry_sheets() stops at Sheet1 before reaching the comparison step.
#
#   VALUE TYPOS in Sheet2 vs Sheet1 (visible once the column issue is bypassed
#   by comparing on the original common columns):
#     Row 61 — Subplot:     TCAM (S1)  vs PCAM (S2)
#     Row  7 — SuctionRate: 2    (S1)  vs 3    (S2)
#     Row 15 — SuctionRate: 2    (S1)  vs 10   (S2)
#     Row 59 — Time:        870  (S1)  vs 260  (S2)
#     Row 13 — Volume:      61   (S1)  vs 96   (S2)
#     Row 63 — Volume:      62.5 (S1)  vs 69   (S2)

test_that("Fixture 20260528: read_entry_sheets stops — Sheet1 missing expected columns", {
  skip_if_not(file.exists(FIXTURE), "fixture not present")
  expect_error(
    read_entry_sheets(FIXTURE),
    "Sheet1 is missing expected column"
  )
})

test_that("Fixture 20260528: Sheet2 has SoilMoisture_12cm in the raw file", {
  skip_if_not(file.exists(FIXTURE), "fixture not present")
  df <- openxlsx::read.xlsx(FIXTURE, sheet = 2)
  expect_true("SoilMoisture_12cm" %in% names(df))
})

test_that("Fixture 20260528: once Sheet1 col issue is bypassed, 6 value typos are in Sheet2", {
  skip_if_not(file.exists(FIXTURE), "fixture not present")
  # Read raw (bypass expected_cols check) to simulate what compare_sheets would see
  # if the structural issue were fixed.
  s1_raw <- openxlsx::read.xlsx(FIXTURE, sheet = 1)
  s2_raw <- openxlsx::read.xlsx(FIXTURE, sheet = 2)
  # Compare on common columns only
  common <- intersect(names(s1_raw), names(s2_raw))
  mismatches <- detect_sheet_mismatches(s1_raw[, common], s2_raw[, common])
  # Exactly 6 differing cells: 1 Subplot, 2 SuctionRate, 1 Time, 2 Volume
  expect_equal(nrow(mismatches), 6L)
})
