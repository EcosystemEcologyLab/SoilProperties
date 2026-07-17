#
# 01_define_rois.R — Interactively define vegetation ROI polygons for each
# trail camera. Run once per camera (and per ROI name) before the main
# pipeline.
#
# Usage (from RStudio with working directory = project root):
#   source("scripts/trailcamera_setup/01_define_rois.R")
#   define_roi("0C", "mesquite")
#   batch_define_rois("2C", c("mesquite", "grass"))
#
# Output locations (git-tracked):
#   data/reference/trailcamera/<camera_id>/roi_<roi_name>_mask.rds
#   data/reference/trailcamera/<camera_id>/roi_<roi_name>_polygon.rds
#
# NOTE: ROI_REFERENCE_DIR in trailcamera_config.R resolves to
#   data/reference/trailcamera_roi/ (note _roi suffix). This script uses
#   data/reference/trailcamera/ as specified in the pipeline design doc —
#   the two paths need to be reconciled in a future config update.
#
# QC figures (gitignored):
#   figures/qc/trailcamera_roi_check_<camera_id>_<roi_name>.png

source("scripts/functions_config/trailcamera_config.R")

# ── Ray-casting point-in-polygon ─────────────────────────────────────────────

#' Test whether a point lies inside a polygon using the ray-casting algorithm.
#'
#' Casts a horizontal ray from \code{(px, py)} in the +x direction and counts
#' the number of polygon edge crossings. An odd count means the point is
#' inside (Jordan curve theorem). Behaviour exactly on the polygon boundary
#' is implementation-defined and should not be relied upon.
#'
#' @param px Numeric scalar. x-coordinate of the test point.
#' @param py Numeric scalar. y-coordinate of the test point.
#' @param poly_x Numeric vector. x-coordinates of polygon vertices in order.
#' @param poly_y Numeric vector. y-coordinates of polygon vertices in order.
#'   Must have the same length as \code{poly_x}. The polygon is implicitly
#'   closed: the last vertex connects back to the first.
#' @return Logical scalar. \code{TRUE} if \code{(px, py)} lies inside the
#'   polygon.
point_in_polygon <- function(px, py, poly_x, poly_y) {
  n      <- length(poly_x)
  inside <- FALSE
  j      <- n
  for (i in seq_len(n)) {
    xi <- poly_x[i]; yi <- poly_y[i]
    xj <- poly_x[j]; yj <- poly_y[j]
    if (((yi > py) != (yj > py)) &&
        (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) {
      inside <- !inside
    }
    j <- i
  }
  inside
}

# ── Polygon rasterization ─────────────────────────────────────────────────────

#' Rasterize a polygon into a logical pixel mask.
#'
#' Applies the ray-casting algorithm vectorised over the full pixel grid
#' (one R loop iteration per polygon edge, not per pixel). Polygon
#' coordinates must be in the same plot-coordinate space returned by
#' \code{\link[graphics]{locator}} when the image is displayed with
#' \code{xlim = c(0, width)}, \code{ylim = c(0, height)}: x increases
#' rightward, y increases upward.
#'
#' The returned matrix is in image-array order: \code{mask[r, c]} is
#' \code{TRUE} when the centre of pixel at row \code{r}, column \code{c}
#' (1-indexed, row 1 = top of image) lies inside the polygon.
#'
#' @param poly_x Numeric vector. x-coordinates of polygon vertices in plot
#'   coordinate space.
#' @param poly_y Numeric vector. y-coordinates of polygon vertices in plot
#'   coordinate space.
#' @param width  Integer scalar. Image width in pixels.
#' @param height Integer scalar. Image height in pixels.
#' @return Logical matrix of dimensions \code{height} \eqn{\times}
#'   \code{width}.
rasterize_polygon <- function(poly_x, poly_y, width, height) {
  # Pixel centres in plot coordinate space:
  #   col c → plot-x = c - 0.5
  #   row r → plot-y = height - r + 0.5  (row 1 is at the image top = ytop)
  # Layout: px_grid and py_grid are both length (width * height).
  # Index (c-1)*height + r corresponds to image pixel (row=r, col=c),
  # so matrix(..., nrow=height, ncol=width) fills correctly (column-major).
  px_grid <- rep(seq_len(width)  - 0.5,        each  = height)
  py_grid <- rep(height - seq_len(height) + 0.5, times = width)

  n      <- length(poly_x)
  inside <- logical(height * width)
  j      <- n
  for (i in seq_len(n)) {
    xi <- poly_x[i]; yi <- poly_y[i]
    xj <- poly_x[j]; yj <- poly_y[j]
    cross  <- ((yi > py_grid) != (yj > py_grid)) &
              (px_grid < (xj - xi) * (py_grid - yi) / (yj - yi) + xi)
    inside <- xor(inside, cross)
    j <- i
  }
  matrix(inside, nrow = height, ncol = width)
}

# ── Image loading ─────────────────────────────────────────────────────────────

# JPEG and PNG only at this step — magick is introduced in 03_process_images.R.
.load_image <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("jpg", "jpeg")) {
    if (!requireNamespace("jpeg", quietly = TRUE)) {
      stop(
        "Package 'jpeg' is required to read JPEG images. ",
        "Install it with install.packages(\"jpeg\").",
        call. = FALSE
      )
    }
    jpeg::readJPEG(path)
  } else if (ext == "png") {
    if (!requireNamespace("png", quietly = TRUE)) {
      stop(
        "Package 'png' is required to read PNG images. ",
        "Install it with install.packages(\"png\").",
        call. = FALSE
      )
    }
    png::readPNG(path)
  } else {
    stop(
      "Unsupported image format '.", ext, "'. ",
      "Only JPEG and PNG are supported at this pipeline step.",
      call. = FALSE
    )
  }
}

# ── Reference image resolution ────────────────────────────────────────────────

# Calls .resolve_trailcam_raw_dir() fresh (not the source-time snapshot
# RAW_IMAGE_DIR) so this still works if the env var was set after sourcing.
.first_camera_image <- function(camera_id) {
  raw_dir <- .resolve_trailcam_raw_dir()
  cam_dir <- file.path(raw_dir, camera_id)
  imgs    <- sort(list.files(
    cam_dir,
    pattern     = "\\.(jpg|jpeg|png)$",
    ignore.case = TRUE,
    full.names  = TRUE
  ))
  if (length(imgs) == 0) {
    stop(
      "No JPEG or PNG images found in ", cam_dir, ". ",
      "Check that the network drive is mounted and camera folder exists.",
      call. = FALSE
    )
  }
  imgs[[1L]]
}

# ── define_roi ────────────────────────────────────────────────────────────────

#' Interactively define a vegetation ROI polygon for one trail camera.
#'
#' Displays a reference image in a graphics window and collects polygon
#' vertices via mouse clicks. Rasterizes the polygon into a logical pixel
#' mask and saves the mask and the raw clicked coordinates to
#' \code{data/reference/trailcamera/<camera_id>/}. A QC confirmation PNG
#' with the ROI boundary overlaid is written to \code{figures/qc/}.
#'
#' @section Interaction:
#' Left-click to add polygon vertices. Right-click or press Esc when done.
#' A minimum of 3 vertices is required to form a valid polygon.
#'
#' @section Coordinate system:
#' Polygon coordinates (\code{$polygon$x}, \code{$polygon$y}) are in plot
#' space: x in \code{[0, width]}, y in \code{[0, height]}, y increases
#' upward. The pixel mask is in image-array order (row 1 = top).
#'
#' @param camera_id Character scalar. Must be a member of \code{CAMERA_IDS}
#'   from \code{trailcamera_config.R}.
#' @param roi_name Character scalar. Short identifier for this ROI (e.g.
#'   \code{"mesquite"}, \code{"grass"}). Used verbatim in output filenames.
#' @param reference_image_path Character scalar or \code{NULL} (default).
#'   Path to a JPEG or PNG image to display. When \code{NULL}, defaults to
#'   the first image alphabetically under
#'   \code{file.path(RAW_IMAGE_DIR, camera_id)}.
#' @return Named list with elements \code{mask} (logical matrix,
#'   height \eqn{\times} width) and \code{polygon} (list with \code{$x}
#'   and \code{$y} in plot coordinate space), invisibly.
define_roi <- function(camera_id, roi_name, reference_image_path = NULL) {
  if (!interactive()) {
    stop(
      "define_roi() must be run interactively from RStudio — ",
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
    "\n── Define ROI ─────────────────────────────────────────────────\n",
    "  Camera : ", camera_id,           "\n",
    "  ROI    : ", roi_name,            "\n",
    "  Image  : ", reference_image_path, "\n",
    "───────────────────────────────────────────────────────────────\n",
    "  Left-click to add polygon vertices (minimum 3 required).\n",
    "  Right-click or press Esc to finish.\n\n",
    sep = ""
  )

  op <- par(mar = c(0, 0, 2, 0))
  on.exit(par(op), add = TRUE)
  plot(
    c(0, width), c(0, height),
    type = "n", xlab = "", ylab = "", asp = 1, axes = FALSE,
    main = paste0("Camera: ", camera_id, "   ROI: ", roi_name)
  )
  rasterImage(img, 0, 0, width, height)

  pts <- locator(type = "l")

  if (is.null(pts) || length(pts$x) < 3L) {
    stop(
      "ROI definition cancelled or insufficient vertices (minimum 3). Got ",
      if (is.null(pts)) 0L else length(pts$x), ".",
      call. = FALSE
    )
  }

  polygon(
    pts$x, pts$y,
    border = "#FF0000", lwd = 2,
    col    = adjustcolor("#FF0000", alpha.f = 0.15)
  )

  mask <- rasterize_polygon(pts$x, pts$y, width, height)

  mask_path    <- file.path(out_dir, paste0("roi_", roi_name, "_mask.rds"))
  polygon_path <- file.path(out_dir, paste0("roi_", roi_name, "_polygon.rds"))
  saveRDS(mask,                        mask_path)
  saveRDS(list(x = pts$x, y = pts$y), polygon_path)

  qc_png_path <- file.path(
    qc_dir,
    paste0("trailcamera_roi_check_", camera_id, "_", roi_name, ".png")
  )
  grDevices::png(qc_png_path, width = width, height = height)
  par(mar = c(0, 0, 2, 0))
  plot(
    c(0, width), c(0, height),
    type = "n", xlab = "", ylab = "", asp = 1, axes = FALSE,
    main = paste0("ROI check — camera: ", camera_id, "   ROI: ", roi_name)
  )
  rasterImage(img, 0, 0, width, height)
  polygon(
    pts$x, pts$y,
    border = "#FF0000", lwd = 2,
    col    = adjustcolor("#FF0000", alpha.f = 0.15)
  )
  grDevices::dev.off()

  message(
    "define_roi complete: camera=", camera_id, " roi=", roi_name, "\n",
    "  Mask    → ", mask_path,    "\n",
    "  Polygon → ", polygon_path, "\n",
    "  QC PNG  → ", qc_png_path
  )

  invisible(list(mask = mask, polygon = list(x = pts$x, y = pts$y)))
}

# ── batch_define_rois ─────────────────────────────────────────────────────────

#' Define multiple ROIs for one camera in a single interactive session.
#'
#' Calls \code{\link{define_roi}} sequentially for each element of
#' \code{roi_names}. Useful when a camera frame contains more than one
#' species ROI (e.g. a canopy patch and a grass patch in the same view).
#'
#' @param camera_id Character scalar. Passed unchanged to
#'   \code{\link{define_roi}}.
#' @param roi_names Character vector. ROI name strings to define in order.
#' @return \code{NULL} invisibly.
batch_define_rois <- function(camera_id, roi_names) {
  if (!interactive()) {
    stop(
      "batch_define_rois() must be run interactively from RStudio.",
      call. = FALSE
    )
  }
  for (roi_name in roi_names) {
    define_roi(camera_id, roi_name)
  }
  message(
    "batch_define_rois complete: ", length(roi_names),
    " ROI(s) defined for camera ", camera_id, "."
  )
  invisible(NULL)
}
