# Root all tests at the project directory so the pipeline's relative paths
# (data/reference/..., outputs/..., R/...) resolve correctly.
# testthat sets getwd() to the test directory (tests/testthat/) before sourcing
# helpers, so two dirname() steps always reach the project root.
.root <- dirname(dirname(normalizePath(getwd(), winslash = "/")))
source(file.path(.root, "scripts", "functions_config", "find_project_root.R"))
rm(.root)

PROJECT_ROOT <- .find_project_root()
setwd(PROJECT_ROOT)

# Shared math + config (sourced once; individual tests source scripts as needed).
source(file.path(PROJECT_ROOT, "scripts", "functions_config", "infiltration_math.R"))
