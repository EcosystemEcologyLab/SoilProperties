# Tests for A_coefficient() in R/infiltration_math.R.
#
# Reference: METER Group "Determining Soil Hydraulic Conductivity" calculation
# workbook.  Every expected value here can be reproduced by entering the same
# alpha / n / r / suction inputs into the METER Excel sheet (cells I31/J31).
# The workbook is the source of truth for the math; these tests guard against
# accidental changes to the formula in infiltration_math.R.
#
# helper-root.R sources infiltration_math.R and sets the working directory.

test_that("METER cross-check: loamy sand, suction=5 cm, r=2.25 cm gives A ≈ 1.6073", {
  # loamy sand (data/reference/vg_parameters.csv): alpha=0.124, n=2.28
  # suction entered positive; h0 = -suction = -5
  A <- A_coefficient(alpha = 0.124, n = 2.28, r = 2.25, h0 = -5)
  expect_equal(A, 1.6073, tolerance = 0.001)
})

test_that("A_coefficient uses c=2.92 when n >= 1.9 (loamy sand n=2.28)", {
  A_228 <- A_coefficient(alpha = 0.124, n = 2.28, r = 2.25, h0 = -5)
  # Manually construct what c=7.5 would give (wrong branch) to confirm mismatch
  A_wrong_c <- (11.65 * (2.28^0.1 - 1) *
                  exp(7.5 * (2.28 - 1.9) * 0.124 * (-5))) / (0.124 * 2.25)^0.91
  expect_false(isTRUE(all.equal(A_228, A_wrong_c, tolerance = 0.01)))
})

test_that("A_coefficient uses c=7.5 when n < 1.9 (clay n=1.09)", {
  # clay: alpha=0.008, n=1.09 — n < 1.9, so c should be 7.5
  A_clay <- A_coefficient(alpha = 0.008, n = 1.09, r = 2.25, h0 = -3)
  A_correct_c <- (11.65 * (1.09^0.1 - 1) *
                    exp(7.5 * (1.09 - 1.9) * 0.008 * (-3))) / (0.008 * 2.25)^0.91
  expect_equal(A_clay, A_correct_c, tolerance = 1e-10)
})

test_that("A_coefficient: n exactly 1.9 uses c=2.92 (boundary is n < 1.9)", {
  # ifelse(n < 1.9, 7.5, 2.92) → n=1.9 uses 2.92
  A_boundary <- A_coefficient(alpha = 0.05, n = 1.9, r = 2.25, h0 = -2)
  A_c292 <- (11.65 * (1.9^0.1 - 1) *
               exp(2.92 * (1.9 - 1.9) * 0.05 * (-2))) / (0.05 * 2.25)^0.91
  expect_equal(A_boundary, A_c292, tolerance = 1e-10)
})

test_that("A_coefficient returns a positive finite number for all 12 USDA texture classes", {
  vg <- read.csv(file.path(PROJECT_ROOT, "data/reference/vg_parameters.csv"),
                 stringsAsFactors = FALSE)
  for (i in seq_len(nrow(vg))) {
    A <- A_coefficient(alpha = vg$alpha[i], n = vg$n[i], r = 2.25, h0 = -3)
    expect_true(is.finite(A) && A > 0,
                info = paste("soil type:", vg$soil_type[i]))
  }
})

test_that("A_coefficient h0 direction: n>1.9 (loamy sand) A decreases, n<1.9 (clay) A increases with deeper suction", {
  # For n > 1.9 (c = 2.92): exponent = 2.92*(n-1.9)*alpha*h0 is negative
  #   (n-1.9 > 0, alpha > 0, h0 < 0), so more negative h0 → smaller A.
  A_ls_h2 <- A_coefficient(alpha = 0.124, n = 2.28, r = 2.25, h0 = -2)
  A_ls_h5 <- A_coefficient(alpha = 0.124, n = 2.28, r = 2.25, h0 = -5)
  expect_lt(A_ls_h5, A_ls_h2)

  # For n < 1.9 (c = 7.5): exponent = 7.5*(n-1.9)*alpha*h0 is positive
  #   (n-1.9 < 0, h0 < 0), so more negative h0 → larger A.
  A_cl_h2 <- A_coefficient(alpha = 0.008, n = 1.09, r = 2.25, h0 = -2)
  A_cl_h5 <- A_coefficient(alpha = 0.008, n = 1.09, r = 2.25, h0 = -5)
  expect_gt(A_cl_h5, A_cl_h2)
})

test_that("cumulative_infiltration scales linearly with volume drop", {
  r <- 2.25
  I <- cumulative_infiltration(V0 = 90, V_t = c(90, 80, 70, 60), r = r)
  expected <- c(0, 10, 20, 30) / (pi * r^2)
  expect_equal(I, expected, tolerance = 1e-10)
})

test_that("cumulative_infiltration returns 0 when V_t == V0", {
  expect_equal(cumulative_infiltration(V0 = 85, V_t = 85, r = 2.25), 0)
})
