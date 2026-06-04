# Root all tests at the project directory so the pipeline's relative paths
# (data/reference/..., outputs/..., R/...) resolve correctly.

.find_root <- function(start = getwd()) {
  d <- normalizePath(start, winslash = "/")
  while (!file.exists(file.path(d, "CLAUDE.md"))) {
    parent <- dirname(d)
    if (parent == d) stop("Could not find project root (no CLAUDE.md found above ", start, ")")
    d <- parent
  }
  d
}

PROJECT_ROOT <- .find_root()
setwd(PROJECT_ROOT)

# Shared math + config (sourced once; individual tests source scripts as needed).
source(file.path(PROJECT_ROOT, "R", "infiltration_math.R"))

#' Write a minimal infiltration field sheet for tests, matching the layout the
#' reader in R/01_qaqc_entry.R expects.
#'
#' @param path Destination .xlsx path.
#' @param meta Named list with site, date, suction (and optional observers).
#' @param blocks List of data.frames, each with columns plot, point_id,
#'   soil_type, time_s, volume_ml (one data block each).
write_test_sheet <- function(path, meta, blocks) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) skip("openxlsx not installed")
  wb <- openxlsx::createWorkbook()
  sh <- "Infiltration"
  openxlsx::addWorksheet(wb, sh)

  meta_df <- data.frame(
    label = c("Site", "Date", "Time Start", "Time End",
              "Suction Rate (cm)", "Observers", "Notes"),
    value = c(meta$site, meta$date, "09:00", "09:30",
              as.character(meta$suction),
              ifelse(is.null(meta$observers), "QA", meta$observers),
              ifelse(is.null(meta$notes), "", meta$notes)),
    stringsAsFactors = FALSE)
  openxlsx::writeData(wb, sh, meta_df, startRow = 2, startCol = 1, colNames = FALSE)

  cur <- nrow(meta_df) + 4
  hdr <- c("Plot", "Point ID", "SoilType", "Time (sec)", "Volume (mL)")
  for (b in blocks) {
    openxlsx::writeData(wb, sh, as.data.frame(t(hdr)), startRow = cur,
                        startCol = 1, colNames = FALSE)
    block <- data.frame(
      plot = b$plot, point_id = b$point_id, soil_type = b$soil_type,
      time_s = b$time_s, volume_ml = b$volume_ml, stringsAsFactors = FALSE)
    openxlsx::writeData(wb, sh, block, startRow = cur + 1, startCol = 1,
                        colNames = FALSE)
    cur <- cur + nrow(block) + 3   # gap before next block
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}

#' Run script 01 on a fixture with logs/outputs redirected to a temp dir.
#' Returns list(exclusion = <df>, unknown = <df>, clean_path = <chr>).
run_qaqc_isolated <- function(meta, blocks) {
  # testthat::test_file() changes the working directory to the test file's
  # directory before running tests; source("R/...") inside the pipeline scripts
  # is relative to the project root, so we pin it here.
  old_wd <- setwd(PROJECT_ROOT)
  on.exit(setwd(old_wd), add = TRUE)
  source(file.path(PROJECT_ROOT, "R", "01_qaqc_entry.R"), local = FALSE)
  tmp <- tempfile("qaqc_"); dir.create(tmp)
  sheet <- file.path(tmp, "sheet.xlsx")
  write_test_sheet(sheet, meta, blocks)

  # redirect outputs into the temp dir
  old <- list(PATH_OUTPUTS, PATH_EXCLUSION_LOG, PATH_UNKNOWN_LOG, PATH_PROCESSED)
  PATH_OUTPUTS       <<- file.path(tmp, "outputs")
  PATH_EXCLUSION_LOG <<- file.path(PATH_OUTPUTS, "exclusion_log.csv")
  PATH_UNKNOWN_LOG   <<- file.path(PATH_OUTPUTS, "unknown_log.csv")
  PATH_PROCESSED     <<- file.path(tmp, "processed")
  on.exit({
    PATH_OUTPUTS       <<- old[[1]]
    PATH_EXCLUSION_LOG <<- old[[2]]
    PATH_UNKNOWN_LOG   <<- old[[3]]
    PATH_PROCESSED     <<- old[[4]]
  }, add = TRUE)

  clean_path <- suppressMessages(run_qaqc_entry(sheet))
  rd <- function(p) if (file.exists(p)) read.csv(p, stringsAsFactors = FALSE) else
    data.frame()
  list(exclusion = rd(PATH_EXCLUSION_LOG),
       unknown   = rd(PATH_UNKNOWN_LOG),
       clean_path = clean_path)
}
