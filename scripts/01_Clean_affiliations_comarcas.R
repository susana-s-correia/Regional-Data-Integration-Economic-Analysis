# =====================================================
# Project: Regionalization of Input-Output Tables

# Script: 01_clean_affiliations_comarcas.R

# Objective:
#Read and clean General Regime and RETA (self-employed workers) affiliation data
#to create an analysis-ready dataset.
#Data are provided at the comarca and Aran levels.
#
# =====================================================
getwd()
setwd("C:/Users/Proprietário/Documents/PERSONAL/ESPAÑA/Trabajo con Angels/Datos")

library(readxl)

general <- read_excel("Demograficos y economicos/afiliaciones_segsocial_regeneral_comarcas.xlsx", sheet = "Datos", skip = 1)
autonomos <- read_excel("Demograficos y economicos/afiliaciones_segsocial_autonomos_comarcas.xlsx", sheet = "Datos", skip = 1)

# ============================================================
# 1. Inspect and clean the input data
# ============================================================

names(general)
names(autonomos)

dim(general)
dim(autonomos)

head(general)
head(autonomos)

# Check the data types of the yearly affiliation columns.
# Some columns were imported as characters rather than numeric values.
sapply(general[, c("12/2025", "12/2024", "12/2023", "12/2022", "12/2021")], class)

# Inspect the unique values in the affected columns to identify
# non-numeric entries or other unexpected values.
unique(general$`12/2022`)
unique(general$`12/2021`)
unique(general$`12/2023`)

# Identify rows containing missing values (NAs) in the 2022 column.
general[is.na(general$`12/2022`), ]


# ============================================================
# 2. Rename columns
# ============================================================

# Rename the columns to make them easier to work with in R.
names(general) <- c(
  "sector",
  "comarca",
  "af_2025",
  "af_2024",
  "af_2023",
  "af_2022",
  "af_2021"
)

names(autonomos) <- c(
  "sector",
  "comarca",
  "af_2025",
  "af_2024",
  "af_2023",
  "af_2022",
  "af_2021"
)


# ============================================================
# 3. Load required packages
# ============================================================

library(tidyverse)


# ============================================================
# 4. Fill missing sector names
# ============================================================

# Fill missing sector values using the value from the previous row.
# This is necessary because the original data contain sector names
# only at the beginning of each sector group.
general <- general %>%
  fill(sector)

autonomos <- autonomos %>%
  fill(sector)


# ============================================================
# 5. Remove unnecessary rows
# ============================================================

# Remove the last 8 rows, which contain information that is not
# part of the affiliation dataset.
general <- general %>%
  slice(1:(n() - 8))

autonomos <- autonomos %>%
  slice(1:(n() - 8))


# ============================================================
# 6. Convert affiliation data to numeric
# ============================================================

# The yearly affiliation columns were not all imported as numeric.
# Non-numeric entries (e.g. "..") are converted to NA.
general[, 3:ncol(general)] <-
  lapply(general[, 3:ncol(general)], as.numeric)

autonomos[, 3:ncol(autonomos)] <-
  lapply(autonomos[, 3:ncol(autonomos)], as.numeric)


# Check the unique values in the 2021 affiliation column.
unique(autonomos$af_2021)

# Check the data types of all columns.
sapply(general, class)

# Count missing values in each column.
colSums(is.na(general))

# Identify rows with missing 2021 affiliation values.
autonomos %>%
  filter(is.na(af_2021))


# ============================================================
# 7. Combine General Regime and self-employed affiliations
# ============================================================

# Start with the General Regime dataset as the base table.
afiliaciones <- general

# Add General Regime and self-employed affiliations for each year.
# The resulting table contains total affiliations by sector and comarca.
afiliaciones[, 3:ncol(afiliaciones)] <-
  general[, 3:ncol(general)] +
  autonomos[, 3:ncol(autonomos)]


# ============================================================
# 8. Validate the resulting dataset
# ============================================================

# Check that the affiliation columns are numeric.
sapply(afiliaciones, class)

# Check the number of missing values in each column.
colSums(is.na(afiliaciones))

# Identify rows with missing 2021 affiliation values.
afiliaciones %>%
  filter(is.na(af_2021))


# ============================================================
# 9. Export the cleaned dataset
# ============================================================

library(writexl)

write_xlsx(
  afiliaciones,
  "Output/affiliations_total_comarcas.xlsx"
)


