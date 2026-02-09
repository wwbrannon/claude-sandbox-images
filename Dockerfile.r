# Claude Code Sandbox - R Variant
# Base image + R ecosystem
FROM claude-sandbox-minimal

# Switch to root for installations
USER root

## Install lib dependencies, R/headers/base+recommended, CRAN packages
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libxml2-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
    \
    r-base r-base-dev r-recommended littler \
    \
    r-cran-tidyverse \
    \
    r-cran-patchwork r-cran-scales \
    \
    r-cran-devtools r-cran-usethis r-cran-testthat r-cran-roxygen2 \
    r-cran-rmarkdown r-cran-knitr r-cran-pak r-cran-renv \
    \
    r-cran-data.table r-cran-arrow \
    r-cran-readxl r-cran-writexl r-cran-haven r-cran-jsonlite r-cran-yaml \
    \
    r-cran-dbi r-cran-duckdb r-cran-rsqlite r-cran-odbc \
    \
    r-cran-lubridate r-cran-janitor \
    \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Don't set USER here - entrypoint.sh handles user switching
WORKDIR /workspace
