#
# 02_define_timestamp_crop.R — Interactively define the timestamp banner crop
# region for each trail camera. Run once per camera before the main pipeline.
#
# Usage (from RStudio with working directory = project root):
#   source("scripts/trailcamera_setup/02_define_timestamp_crop.R")
#   windows(width = 10, height = 8)
#   define_timestamp_crop("0C")
#
# Output location (git-tracked):
#   data/reference/trailcamera/<camera_id>/timestamp_crop.rds
#
#   The saved list contains x1, y1 (first click) and x2, y2 (second click)
#   in plot coordinate space (x in [0, width], y in [0, height], y upward),
#   plus image_width and image_height for reference. Step 03 converts these
#   to pixel row/column indices for magick cropping.
#
# QC figures (gitignored):
#   figures/qc/trailcamera_timestamp_crop_check_<camera_id>.png
#
# Depends on 01_define_rois.R for .load_image() and .first_camera_image().

source("scripts/functions_config/trailcamera_config.R")
source("scripts/trailcamera_setup/01_define_rois.R")

# ── define_timestamp_crop ─────────────────────────────────────────────────────

#' Interactively define the timestamp banner crop region for one trail camera.
#'
#' Displays a reference image and prompts the user to click two points that
#' bound the date/time text burned into the image frame. The bounding box is
#' saved to \code{data/reference/trailcamera/<camera_id>/timestamp_crop.rds}
#' and a QC confirmation PNG is written to \code{figures/qc/}.
#'
#' @section Interaction:
#' Click exactly two points in either order — the algorithm takes the
#' bounding box of the two clicks, so top-left then bottom-right and
#' bottom-right then top-left both work.
#'
#' @section Saved format:
#' An RDS list with elements:
#' \describe{
#'   \item{\code{x1}, \code{y1}}{First clicked point in plot coordinate
#'     space (x in \code{[0, width]}, y in \code{[0, height]}, y upward).}
#'   \item{\code{x2}, \code{y2}}{Second clicked point.}
#'   \item{\code{image_width}, \code{image_height}}{Dimensions of the
#'     reference image, used by step 03 to convert plot coords to pixel
#'     indices.}
#' }
#'
#' @param camera_id Character scalar. Must be a member of \code{CAMERA_IDS}
#'   from \code{trailcamera_config.R}.
#' @param reference_image_path Character scalar or \code{NULL} (default).
#'   Path to a JPEG or PNG image to display. When \code{NULL}, defaults to
#'   the first image alphabetically under
#'   \code{file.path(RAW_IMAGE_DIR, camera_id)}.
#' @return Named list with elements \code{x1}, \code{y1}, \code{x2},
#'   \code{y2}, \code{image_width}, \code{image_height}, invisibly.
define_timestamp_crop <- function(camera_id, reference_image_path = NULL) {
  if (!interactive()) {
    stop(
      "define_timestamp_crop() must be run interactively from RStudio — ",
      "it requires mouse input via locator().",
      call. = FALSE
    )
  }

  check_trailcamera_config()

  if (!camera_id %in% CAMERA_IDS) {
    stop(
      "Unknown camera_id '", camera_id, "'. ",
      "Must be one of: ", paste(CAMERA_IDS, collapse = ", "), ".",
      call. = FALSE
    )
  }

  if (is.null(reference_image_path)) {
    reference_image_path <- .first_camera_image(camera_id)
  }
  if (!file.exists(reference_image_path)) {
    stop("Reference image not found: ", reference_image_path, call. = FALSE)
  }

  img    <- .load_image(reference_image_path)
  height <- dim(img)[1L]
  width  <- dim(img)[2L]

  out_dir <- file.path("data", "reference", "trailcamera", camera_id)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  qc_dir <- file.path("figures", "qc")
  if (!dir.exists(qc_dir)) dir.create(qc_dir, recursive = TRUE)

  cat(
    "\n── Define timestamp crop ──────────────────────────────────────\n",
    "  Camera : ", camera_id,            "\n",
    "  Image  : ", reference_image_path, "\n",
    "───────────────────────────────────────────────────────────────\n",
    "  Click TWO points that bound the date/time banner:\n",
    "    Click 1 — any corner of the timestamp region.\n",
    "    Click 2 — the opposite corner.\n\n",
    sep = ""
  )

  op <- par(mar = c(0, 0, 2, 0))
  on.exit(par(op), add = TRUE)
  plot(
    c(0, width), c(0, height),
    type = "n", xlab = "", ylab = "", asp = 1, axes = FALSE,
    main = paste0("Camera: ", camera_id, "   — click two corners of the timestamp banner")
  )
  rasterImage(img, 0, 0, width, height)

  pts <- locator(2L, type = "p", pch = 3L, col = "cyan", cex = 2)

  if (is.null(pts) || length(pts$x) < 2L) {
    stop(
      "Timestamp crop cancelled or insufficient clicks (exactly 2 required). Got ",
      if (is.null(pts)) 0L else length(pts$x), ".",
      call. = FALSE
    )
  }

  rect(
    min(pts$x), min(pts$y), max(pts$x), max(pts$y),
    border = "cyan", lwd = 2
  )

  crop <- list(
    x1           = pts$x[[1L]],
    y1           = pts$y[[1L]],
    x2           = pts$x[[2L]],
    y2           = pts$y[[2L]],
    image_width  = width,
    image_height = height
  )

  crop_path <- file.path(out_dir, "timestamp_crop.rds")
  saveRDS(crop, crop_path)

  qc_png_path <- file.path(
    qc_dir,
    paste0("trailcamera_timestamp_crop_check_", camera_id, ".png")
  )
  grDevices::png(qc_png_path, width = width, height = height)
  par(mar = c(0, 0, 2, 0))
  plot(
    c(0, width), c(0, height),
    type = "n", xlab = "", ylab = "", asp = 1, axes = FALSE,
    main = paste0("Timestamp crop check — camera: ", camera_id)
  )
  rasterImage(img, 0, 0, width, height)
  rect(
    min(pts$x), min(pts$y), max(pts$x), max(pts$y),
    border = "cyan", lwd = 2
  )
  grDevices::dev.off()

  message(
    "define_timestamp_crop complete: camera=", camera_id, "\n",
    "  Crop   → ", crop_path,    "\n",
    "  QC PNG → ", qc_png_path
  )

  invisible(crop)
}
