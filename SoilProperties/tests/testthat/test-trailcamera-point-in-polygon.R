# Tests for point_in_polygon() defined in 01_define_rois.R.
#
# These are pure-logic tests: no real images, no network drive, no locator().
# point_in_polygon() takes only numeric arguments and has no side effects,
# so it can be tested without the interactive guard or a network mount.
#
# helper-root.R has already set PROJECT_ROOT and setwd(PROJECT_ROOT).
# testthat resets wd to the test directory before running each file, so we
# must restore PROJECT_ROOT before sourcing 01_define_rois.R — that file uses
# a bare relative path for its own source() calls (correct for RStudio use).
withr::local_dir(PROJECT_ROOT)
suppressMessages(
  source(file.path(PROJECT_ROOT, "scripts", "trailcamera_setup",
                   "01_define_rois.R"))
)

# ── Axis-aligned square ───────────────────────────────────────────────────────
# Vertices (counter-clockwise): (1,1), (5,1), (5,5), (1,5)

sq_x <- c(1, 5, 5, 1)
sq_y <- c(1, 1, 5, 5)

test_that("point clearly inside a square returns TRUE", {
  expect_true(point_in_polygon(3, 3, sq_x, sq_y))
})

test_that("point clearly outside a square (left) returns FALSE", {
  expect_false(point_in_polygon(0, 3, sq_x, sq_y))
})

test_that("point clearly outside a square (right) returns FALSE", {
  expect_false(point_in_polygon(6, 3, sq_x, sq_y))
})

test_that("point clearly outside a square (below) returns FALSE", {
  expect_false(point_in_polygon(3, 0, sq_x, sq_y))
})

test_that("point clearly outside a square (above) returns FALSE", {
  expect_false(point_in_polygon(3, 6, sq_x, sq_y))
})

test_that("point at origin (well outside square) returns FALSE", {
  expect_false(point_in_polygon(0, 0, sq_x, sq_y))
})

# ── Non-convex polygon (L-shape) ──────────────────────────────────────────────
# Vertices (clockwise from origin):
#   (0,0) → (4,0) → (4,2) → (2,2) → (2,4) → (0,4)
# The upper-right quadrant [2,4]×[2,4] is the missing notch.

lx <- c(0, 4, 4, 2, 2, 0)
ly <- c(0, 0, 2, 2, 4, 4)

test_that("point in lower-left arm of L-shape is inside", {
  expect_true(point_in_polygon(1, 1, lx, ly))
})

test_that("point in upper-left arm of L-shape is inside", {
  expect_true(point_in_polygon(1, 3, lx, ly))
})

test_that("point in the notch (upper-right) of L-shape is outside", {
  expect_false(point_in_polygon(3, 3, lx, ly))
})

test_that("point well outside L-shape is outside", {
  expect_false(point_in_polygon(5, 5, lx, ly))
})

# ── Boundary behaviour ────────────────────────────────────────────────────────
# The ray-casting algorithm's behaviour exactly on the polygon boundary is
# implementation-defined. These tests document the current behaviour rather
# than asserting a normative contract.

test_that("boundary behaviour on a horizontal edge is consistent across calls", {
  # Point on the bottom edge of the square y=1, x=3.
  result <- point_in_polygon(3, 1, sq_x, sq_y)
  expect_type(result, "logical")
  expect_length(result, 1L)
  # Repeat call must return the same value (deterministic).
  expect_identical(result, point_in_polygon(3, 1, sq_x, sq_y))
})

test_that("boundary behaviour on a vertical edge is consistent across calls", {
  result <- point_in_polygon(1, 3, sq_x, sq_y)
  expect_type(result, "logical")
  expect_length(result, 1L)
  expect_identical(result, point_in_polygon(1, 3, sq_x, sq_y))
})
