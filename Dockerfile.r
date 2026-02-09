# Claude Code Sandbox - R Variant
# Base image + R ecosystem
FROM claude-sandbox-base

# Switch to root for installations
USER root

# Install R and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base \
    r-base-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN R -e "install.packages(c( \
    'tidyverse', \
    'ggplot2', \
    'dplyr', \
    'tidyr', \
    'readr', \
    'purrr', \
    'tibble', \
    'stringr', \
    'forcats', \
    'devtools', \
    'testthat', \
    'rmarkdown', \
    'knitr' \
    ), repos='https://cloud.r-project.org/')"

# Switch back to agent user
USER agent
WORKDIR /workspace
