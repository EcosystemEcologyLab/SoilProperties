# =============================================================================
# infiltration_math.R — MiniDisk infiltrometer equations (reimplemented from the
# METER calculation workbook; the workbook is the source of truth for the math
# only — it is NOT a runtime dependency).
#
# Sourced by R/02_calculate_infiltration.R and by the testthat tests.
# Pure functions, base R only — no side effects, no global state.
# =============================================================================

#' Cumulative infiltration I_t in cm for a MiniDisk reading.
#'
#' I_t = (V0 - V_t) / (pi * r^2), with volumes in mL (= cm^3) and r in cm.
#'
#' @param V0 Numeric; reservoir volume at t = 0 (mL).
#' @param V_t Numeric vector; reservoir volume at time t (mL).
#' @param r Numeric; infiltrometer disk radius (cm).
#' @return Numeric vector of cumulative infiltration (cm).
cumulative_infiltration <- function(V0, V_t, r) {
  (V0 - V_t) / (pi * r^2)
}

#' Van Genuchten / Zhang (1997) A coefficient (METER sheet cell J31).
#'
#' A = 11.65 * (n^0.1 - 1) * exp(c * (n - 1.9) * alpha * h0) / (alpha * r)^0.91
#' with c = 7.5 if n < 1.9 else 2.92.
#'
#' @param alpha Numeric; van Genuchten alpha (1/cm).
#' @param n Numeric; van Genuchten n (dimensionless).
#' @param r Numeric; infiltrometer disk radius (cm).
#' @param h0 Numeric; suction head at the disk surface (cm), a NEGATIVE number
#'   equal to -suction (suction is entered as a positive value).
#' @return Numeric A coefficient.
A_coefficient <- function(alpha, n, r, h0) {
  cc <- ifelse(n < 1.9, 7.5, 2.92)
  (11.65 * (n^0.1 - 1) * exp(cc * (n - 1.9) * alpha * h0)) / ((alpha * r)^0.91)
}

#' Fit cumulative infiltration to I = C2*sqrt(t) + C1*t with no intercept.
#'
#' Matches LINEST(Infilt, sqrtTime^{1,2}, FALSE) in the METER sheet. Fits a
#' quadratic polynomial in sqrt(t) space with no intercept:
#'   I ~ 0 + sqrt_t + I(sqrt_t^2)
#' where sqrt_t^2 == t. LINEST returns coefficients highest-power first, so
#' the METER sheet assigns the coefficient for t to its "C1" cell and the
#' coefficient for sqrt(t) to its "C2" cell. This function follows that
#' convention: C1 is the linear-in-t term (units cm/s, used directly in
#' K = C1/A), and C2 is the sqrt(t) sorptivity term (units cm/s^0.5).
#'
#' The reported r-squared is the uncentered R^2 that R returns for a
#' no-intercept model, matching the METER LINEST output.
#'
#' @param time_s Numeric vector of times (s).
#' @param I Numeric vector of cumulative infiltration (cm), same length.
#' @return list(C1, C2, r2, n_points). C1/C2/r2 are NA if the fit cannot be
#'   computed (fewer than 2 points or a singular fit).
fit_infiltration <- function(time_s, I) {
  ok <- is.finite(time_s) & is.finite(I)
  time_s <- time_s[ok]; I <- I[ok]
  n_points <- length(I)
  na_out <- list(C1 = NA_real_, C2 = NA_real_, r2 = NA_real_, n_points = n_points)
  if (n_points < 2) return(na_out)

  sqrt_t <- sqrt(time_s)
  fit <- tryCatch(stats::lm(I ~ 0 + sqrt_t + I(sqrt_t^2)), error = function(e) NULL)
  if (is.null(fit)) return(na_out)

  co <- stats::coef(fit)
  C1 <- unname(co["I(sqrt_t^2)"]); C2 <- unname(co["sqrt_t"])
  r2 <- suppressWarnings(summary(fit)$r.squared)
  if (is.null(r2) || length(r2) == 0) r2 <- NA_real_
  list(C1 = C1, C2 = C2, r2 = r2, n_points = n_points)
}
