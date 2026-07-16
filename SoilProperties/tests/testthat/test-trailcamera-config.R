# Tests for scripts/functions_config/trailcamera_config.R.
#
# Contracts tested:
#   1. Sourcing the config in a non-interactive session with
#      TRAILCAM_RAW_IMAGE_DIR unset produces RAW_IMAGE_DIR = NULL (not an
#      error) — the same guarantee recently added to soilinfiltration_config.R.
#   2. check_trailcamera_config() stops loudly when RAW_IMAGE_DIR is NULL.
#   3. check_trailcamera_config() stops and names every missing camera
#      subfolder when they don't all exist under RAW_IMAGE_DIR.
#   4. check_trailcamera_config() returns TRUE invisibly when all 12 camera
#      subdirectories exist.
#
# helper-root.R has already set PROJECT_ROOT and setwd(PROJECT_ROOT).

# Source the config at top level to expose CAMERA_IDS and
# check_trailcamera_config() for use in tests below.
# In this non-interactive environment TRAILCAM_RAW_IMAGE_DIR is unset, so
# RAW_IMAGE_DIR will be NULL and a message will be emitted — both expected.
source(file.path(PROJECT_ROOT, "scripts", "functions_config",
                 "trailcamera_config.R"))

# ── 1. Non-interactive NULL behaviour ─────────────────────────────────────────

test_that("config sources without error and sets RAW_IMAGE_DIR=NULL when env var is unset and non-interactive", {
  old_val <- Sys.getenv("TRAILCAM_RAW_IMAGE_DIR", unset = NA_character_)
  Sys.unsetenv("TRAILCAM_RAW_IMAGE_DIR")
  on.exit({
    if (!is.na(old_val)) Sys.setenv(TRAILCAM_RAW_IMAGE_DIR = old_val)
    else Sys.unsetenv("TRAILCAM_RAW_IMAGE_DIR")
  })

  local_env <- new.env(parent = globalenv())
  expect_error(
    suppressMessages(
      source(file.path(PROJECT_ROOT, "scripts", "functions_config",
                       "trailcamera_config.R"), local = local_env)
    ),
    NA   # expects NO error
  )
  expect_null(local_env$RAW_IMAGE_DIR)
})

# ── 2–4. check_trailcamera_config() ───────────────────────────────────────────

test_that("check_trailcamera_config() stops when RAW_IMAGE_DIR is NULL", {
  expect_error(
    check_trailcamera_config(raw_dir = NULL),
    "RAW_IMAGE_DIR is NULL"
  )
})

test_that("check_trailcamera_config() stops and lists missing camera subfolders", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  # Create only the first two camera dirs; the remaining ten are missing.
  dir.create(file.path(tmp, "0C"))
  dir.create(file.path(tmp, "2C"))

  err_msg <- tryCatch(
    check_trailcamera_config(raw_dir = tmp),
    error = function(e) e$message
  )
  expect_true(grepl("missing", err_msg, ignore.case = TRUE))
  expect_false(grepl("0C", err_msg))  # present — must not be listed
  expect_false(grepl("2C", err_msg))  # present — must not be listed
  expect_true(grepl("3B", err_msg))   # absent  — must be listed
  expect_true(grepl("70", err_msg))   # absent  — must be listed
})

test_that("check_trailcamera_config() returns TRUE invisibly when all camera dirs exist", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  for (cam in CAMERA_IDS) dir.create(file.path(tmp, cam))
  result <- check_trailcamera_config(raw_dir = tmp)
  expect_true(isTRUE(result))
})
