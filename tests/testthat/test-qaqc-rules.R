# Tests for the QC rules applied by run_qaqc_entry() in R/01_qaqc_entry.R.
#
# QC rule order (per script header):
#   1. Controlled vocabulary (soil_type)     empty  -> UNKNOWN; unrecognised -> EXCLUDE
#   2. Numeric ranges (time, volume)         missing -> UNKNOWN; out-of-range  -> EXCLUDE
#   3. Monotonic time (non-decreasing)       violation -> EXCLUDE
#   4. Monotonic volume (non-increasing +1 mL) violation -> EXCLUDE
#   5. Suction in VALID_SUCTIONS_CM          invalid  -> EXCLUDE whole site-date
#   6. t=0 anchor required per replicate     missing  -> UNKNOWN (drop replicate)
#
# Each test uses run_qaqc_isolated() from helper-root.R, which writes a
# temporary field sheet, redirects outputs to a temp dir, calls
# run_qaqc_entry(), and returns the exclusion log, unknown log, and clean CSV
# path.  The fixture builder (write_test_sheet) mirrors the layout that
# read_infiltration_sheet() expects.
#
# helper-root.R sources infiltration_math.R and sets the working directory.

# ---------------------------------------------------------------------------
# Minimal valid block fixture — used as a base in several tests.
# ---------------------------------------------------------------------------
.valid_block <- function(soil = "loamy sand") {
  list(
    plot = rep("A", 6), point_id = rep("P1", 6),
    soil_type = rep(soil, 6),
    time_s    = c(0, 30, 60, 90, 120, 150),
    volume_ml = c(90, 85, 81, 78, 75, 73)
  )
}
.valid_meta <- function(suction = 5) {
  list(site = "B2_Test", date = "2026-06-01", suction = suction)
}

# ---------------------------------------------------------------------------
# QC rule 1: soil_type controlled vocabulary
# ---------------------------------------------------------------------------

test_that("QC1: empty soil_type -> UNKNOWN, not in clean output", {
  # The field sheet forward-fills soil_type downward, so mid-block NAs get
  # filled from the row above. To reach the QC rule, the FIRST row in the
  # block must be NA (nothing above to fill from), leaving the whole replicate
  # with no soil_type.
  block <- .valid_block()
  block$soil_type <- rep(NA_character_, length(block$soil_type))
  res <- run_qaqc_isolated(.valid_meta(), list(block))

  expect_true(any(grepl("soil_type_missing", res$unknown$reason)),
              info = "expected soil_type_missing in unknown log")
})

test_that("QC1: unrecognised soil_type -> EXCLUDE", {
  block <- .valid_block()
  block$soil_type[3:4] <- "moon dust"
  res <- run_qaqc_isolated(.valid_meta(), list(block))

  expect_true(any(grepl("soil_type_unrecognised", res$exclusion$reason)),
              info = "expected soil_type_unrecognised in exclusion log")
})

test_that("QC1: valid soil_type passes through to clean CSV", {
  res <- run_qaqc_isolated(.valid_meta(), list(.valid_block()))
  clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
  expect_gt(nrow(clean), 0)
  expect_true(all(clean$soil_type == "loamy sand"))
})

# ---------------------------------------------------------------------------
# QC rule 2: numeric ranges
# ---------------------------------------------------------------------------

test_that("QC2: NA time_s -> UNKNOWN", {
  block <- .valid_block()
  block$time_s[3] <- NA
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("time_missing", res$unknown$reason)))
})

test_that("QC2: NA volume_ml -> UNKNOWN", {
  block <- .valid_block()
  block$volume_ml[4] <- NA
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("volume_missing", res$unknown$reason)))
})

test_that("QC2: negative time_s -> EXCLUDE", {
  block <- .valid_block()
  block$time_s[2] <- -5
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("time_negative", res$exclusion$reason)))
})

test_that("QC2: negative volume_ml -> EXCLUDE", {
  block <- .valid_block()
  block$volume_ml[3] <- -1
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("volume_negative", res$exclusion$reason)))
})

test_that("QC2: volume_ml > MAX_VOLUME_ML (95 mL) -> EXCLUDE", {
  block <- .valid_block()
  block$volume_ml[2] <- 99
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("volume_exceeds_max", res$exclusion$reason)))
})

# ---------------------------------------------------------------------------
# QC rule 3: monotonic time
# ---------------------------------------------------------------------------

test_that("QC3: time goes backwards within a replicate -> EXCLUDE the offending row", {
  block <- .valid_block()
  block$time_s <- c(0, 30, 60, 40, 120, 150)  # row 4 steps back to t=40
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("non_monotonic_time", res$exclusion$reason)))
})

# ---------------------------------------------------------------------------
# QC rule 4: monotonic volume
# ---------------------------------------------------------------------------

test_that("QC4: volume rises by > 1 mL -> EXCLUDE the offending row", {
  block <- .valid_block()
  block$volume_ml <- c(90, 85, 88, 78, 75, 73)  # row 3: 85->88, rise of 3 mL
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("non_monotonic_volume", res$exclusion$reason)))
})

test_that("QC4: volume rises by <= 1 mL (tolerance) -> NOT excluded", {
  block <- .valid_block()
  block$volume_ml <- c(90, 85, 85.5, 82, 79, 77)  # row 3: rise of 0.5 mL (OK)
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_false(any(grepl("non_monotonic_volume", res$exclusion$reason)))
})

# ---------------------------------------------------------------------------
# QC rule 5: suction must be in VALID_SUCTIONS_CM
# ---------------------------------------------------------------------------

test_that("QC5: invalid suction -> EXCLUDE entire site-date, zero clean rows", {
  meta <- .valid_meta(suction = 99)   # 99 is not in {0.5,1,2,3,4,5,6,7}
  res <- run_qaqc_isolated(meta, list(.valid_block()))
  expect_true(any(grepl("suction_invalid", res$exclusion$reason)))
  clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
  expect_equal(nrow(clean), 0L)
})

test_that("QC5: all 8 valid suction settings pass", {
  for (s in c(0.5, 1, 2, 3, 4, 5, 6, 7)) {
    res <- run_qaqc_isolated(.valid_meta(suction = s), list(.valid_block()))
    expect_false(any(grepl("suction_invalid", res$exclusion$reason)),
                 info = paste("suction =", s))
    clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
    expect_gt(nrow(clean), 0, label = paste("clean rows for suction =", s))
  }
})

# ---------------------------------------------------------------------------
# QC rule 6: t=0 anchor required
# ---------------------------------------------------------------------------

test_that("QC6: replicate without a t=0 row -> UNKNOWN, replicate dropped from clean", {
  block <- .valid_block()
  block$time_s <- c(10, 30, 60, 90, 120, 150)   # no t=0 anchor
  res <- run_qaqc_isolated(.valid_meta(), list(block))
  expect_true(any(grepl("no_t0_anchor", res$unknown$reason)))
  # Replicate should not appear in clean output
  if (file.exists(res$clean_path)) {
    clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
    expect_equal(nrow(clean), 0L)
  }
})

test_that("QC6: replicate with t=0 is preserved in clean output", {
  res <- run_qaqc_isolated(.valid_meta(), list(.valid_block()))
  clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
  expect_true(any(clean$time_s == 0))
})

# ---------------------------------------------------------------------------
# Integration: clean run — no exclusions, no unknowns
# ---------------------------------------------------------------------------

test_that("Clean data: exclusion log is empty and all input rows pass", {
  res <- run_qaqc_isolated(.valid_meta(), list(.valid_block()))
  expect_equal(nrow(res$exclusion), 0L)
  expect_equal(nrow(res$unknown), 0L)
  clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
  # 6 input rows, all should survive
  expect_equal(nrow(clean), 6L)
})

test_that("Clean data: output columns are site, date, plot, point_id, soil_type, suction_cm, time_s, volume_ml, observer, notes", {
  res <- run_qaqc_isolated(.valid_meta(), list(.valid_block()))
  clean <- read.csv(res$clean_path, stringsAsFactors = FALSE)
  expected_cols <- c("site", "date", "plot", "point_id", "soil_type",
                     "suction_cm", "time_s", "volume_ml", "observer", "notes")
  expect_true(all(expected_cols %in% names(clean)))
})
