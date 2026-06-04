# Tests for fit_infiltration() in R/infiltration_math.R.
#
# fit_infiltration(time_s, I) fits I = C1*sqrt(t) + C2*t with no intercept,
# matching the METER LINEST formula.  These tests verify:
#   * correct coefficient recovery on synthetic data
#   * NA handling for degenerate inputs (< 2 points, non-finite values)
#   * the returned r2 is the no-intercept (uncentered) R² that R reports
#     for lm(y ~ 0 + ...), NOT the centred R² Excel reports — see comments below
#   * n_points reflects only finite (time, I) pairs
#
# helper-root.R sources infiltration_math.R and sets the working directory.

test_that("fit_infiltration recovers known C1, C2 from exact synthetic data", {
  # Construct I = 0.05*sqrt(t) + 0.002*t exactly
  C1_true <- 0.05; C2_true <- 0.002
  t <- c(0, 30, 60, 90, 120, 180, 240, 300)
  I <- C1_true * sqrt(t) + C2_true * t

  fit <- fit_infiltration(t, I)
  expect_equal(fit$C1, C1_true, tolerance = 1e-9)
  expect_equal(fit$C2, C2_true, tolerance = 1e-9)
  expect_equal(fit$r2, 1.0, tolerance = 1e-9)
  expect_equal(fit$n_points, length(t))
})

test_that("fit_infiltration returns r2 close to 1 for near-perfect data", {
  set.seed(42)
  t <- c(0, 30, 60, 90, 120, 180)
  I <- 0.07 * sqrt(t) + 0.003 * t + rnorm(length(t), 0, 0.001)
  fit <- fit_infiltration(t, I)
  expect_gt(fit$r2, 0.99)
})

test_that("fit_infiltration returns NA C1/C2/r2 for fewer than 2 finite points", {
  fit_0 <- fit_infiltration(numeric(0), numeric(0))
  expect_true(is.na(fit_0$C1))
  expect_true(is.na(fit_0$C2))
  expect_true(is.na(fit_0$r2))
  expect_equal(fit_0$n_points, 0L)

  fit_1 <- fit_infiltration(30, 0.4)
  expect_true(is.na(fit_1$C1))
  expect_equal(fit_1$n_points, 1L)
})

test_that("fit_infiltration silently drops non-finite (NA, NaN, Inf) pairs", {
  t <- c(0, 30, NA, 90, 120)
  I <- c(0, 0.4, 0.65, NA, 1.1)
  fit <- fit_infiltration(t, I)
  # Drops rows 3 (NA time) and 4 (NA I), leaving 3 finite pairs
  expect_equal(fit$n_points, 3L)
  expect_false(is.na(fit$C1))
})

test_that("fit_infiltration: n_points counts only the finite pairs used in fit", {
  t <- c(0, 30, Inf, 90, 120, 180)
  I <- c(0, 0.4, 0.6, 0.8, 1.0, 1.3)
  fit <- fit_infiltration(t, I)
  expect_equal(fit$n_points, 5L)  # Inf in time is dropped
})

test_that("fit_infiltration returns a list with C1, C2, r2, n_points", {
  fit <- fit_infiltration(c(0, 30, 60, 90, 120), c(0, 0.5, 0.85, 1.1, 1.3))
  expect_named(fit, c("C1", "C2", "r2", "n_points"), ignore.order = FALSE)
})

test_that("fit_infiltration C1 and C2 are numeric scalars (not NA) for valid data", {
  fit <- fit_infiltration(c(0, 30, 60, 90, 120, 150), c(0, 0.4, 0.7, 0.9, 1.1, 1.25))
  expect_true(is.numeric(fit$C1) && length(fit$C1) == 1 && !is.na(fit$C1))
  expect_true(is.numeric(fit$C2) && length(fit$C2) == 1 && !is.na(fit$C2))
})

test_that("fit_infiltration: C1 and C2 scale correctly with I rescaling", {
  # Doubling I should double both C1 and C2 (linear system, no intercept)
  t <- c(0, 30, 60, 90, 120, 180)
  I <- c(0, 0.4, 0.7, 0.9, 1.1, 1.3)
  fit1 <- fit_infiltration(t, I)
  fit2 <- fit_infiltration(t, 2 * I)
  expect_equal(fit2$C1, 2 * fit1$C1, tolerance = 1e-9)
  expect_equal(fit2$C2, 2 * fit1$C2, tolerance = 1e-9)
})
