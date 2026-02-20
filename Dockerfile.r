# Claude Code Sandbox - R Variant
# Base image + R ecosystem
ARG BASE_IMAGE=claude-sandbox-base:latest
FROM ${BASE_IMAGE}

# Switch to root for installations
USER root

# Set up apt repos for updated R and CRAN packages
RUN mkdir -p -m 755 /etc/apt/keyrings && mkdir -p -m 755 /etc/apt/sources.list.d \
    \
    && curl -fsLS https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor > /etc/apt/keyrings/cran-ubuntu.gpg \
    && chmod go+r /etc/apt/keyrings/cran-ubuntu.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/cran-ubuntu.gpg] https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" > /etc/apt/sources.list.d/cran.list \
    \
    && curl -fsLS https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc | gpg --dearmor > /etc/apt/keyrings/r2u.gpg \
    && chmod go+r /etc/apt/keyrings/r2u.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/r2u.gpg] https://r2u.stat.illinois.edu/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/r2u.list

## Install lib dependencies, R/headers/base+recommended, CRAN packages
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libxml2-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev qpdf \
    \
    r-base r-base-dev r-recommended littler \
    \
    r-cran-tidyverse r-cran-r6 \
    \
    r-cran-cli r-cran-docopt r-cran-optparse r-cran-getopt \
    \
    r-cran-patchwork r-cran-scales \
    \
    r-cran-devtools r-cran-usethis r-cran-testthat r-cran-roxygen2 \
    r-cran-rmarkdown r-cran-knitr r-cran-pak r-cran-renv r-cran-bench \
    r-cran-xptr \
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
