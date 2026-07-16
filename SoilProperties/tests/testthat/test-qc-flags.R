# Tests for QC flag logic in .calc_replicate() (scripts/data_processing/calculate_infiltration.R).
#
# helper-root.R sets working dir to project root and sources infiltration_math.R.
# Each test group sources calculate_infiltration.R (which is safe to source
# repeatedly — the if(sys.nframe()==0L) guard prevents auto-execution).

local({
  old <- setwd(PROJECT_ROOT)
  on.exit(setwd(old))
  source(file.path(PROJECT_ROOT, "scripts", "data_processing", "calculate_infiltration.R"))
})

# ── Shared fixtures ────────────────────────────────────────────────────────────

# Fake reference tables used across tests
.fake_vg  <- data.frame(soil_type    = "loam",
                         alpha        = 0.036,
                         n            = 1.56,
                         stringsAsFactors = FALSE)
.fake_tex <- data.frame(subplot      = "TCAM",
                         soil_texture = "loam",
                         stringsAsFactors = FALSE)

# Build a synthetic replicate data frame: I = C2*sqrt(t) + C1*t exactly, so
# the fit returns r² ≈ 1 and C1 > 0.
# C1 is the t-coefficient (METER convention; used for K = C1/A).
# C2 is the sqrt(t) sorptivity coefficient.
.make_rep <- function(C1, C2 = 0.001, soiltype = "TCAM",
                       suction = 2, n = 8) {
  t   <- seq(0, by = 60, length.out = n)
  I   <- C2 * sqrt(t) + C1 * t
  vol <- 80 - I * pi * RADIUS_CM^2
  data.frame(
    Date              = "2026-01-01",
    File              = "test.xlsx",
    SoilType          = soiltype,
    SuctionRate       = suction,
    Time              = t,
    Volume            = vol,
    SoilMoisture_12cm = 10,
    Group             = 1,
    stringsAsFactors  = FALSE
  )
}

# ── REVIEW_high_K ──────────────────────────────────────────────────────────────

test_that("REVIEW_high_K: valid fit with K above loam bound gets REVIEW_high_K, not OK", {
  # C1 = 0.011 cm/s (t-coefficient) gives K ≈ 6.3 cm/hr for loam (bound = 6 cm/hr).
  d   <- .make_rep(C1 = 0.011, C2 = 0.001)
  res <- .calc_replicate(d, .fake_vg, .fake_tex)

  expect_equal(res$qc_flag, "REVIEW_high_K")
  expect_true(res$C1 > 0)
  expect_true(res$r2 >= 0.95)
  expect_false(is.na(res$K_cm_per_hr))
  expect_gt(res$K_cm_per_hr, K_UPPER_CM_HR["Loam"])
})

test_that("OK: valid fit with K at or below loam bound stays OK", {
  # C1 = 0.001 gives K well within the loam bound.
  d   <- .make_rep(C1 = 0.001, C2 = 0.0001)
  res <- .calc_replicate(d, .fake_vg, .fake_tex)

  expect_equal(res$qc_flag, "OK")
  expect_true(res$C1 > 0)
  expect_true(res$r2 >= 0.95)
  expect_lte(res$K_cm_per_hr, K_UPPER_CM_HR["Loam"])
})
