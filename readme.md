# Marine heatvawe index from the NEP 10K ROMS

## Overview

This repository contains scripts for processing ROMS NetCDF output files to create a marine heatwave index (MHWI) for the GOA. Most of the lifting is done to subset and parse the daily NetCDF files (all up we have ~120 TB worth of data).

The approach leverages CDO for efficient processing of the nc files on loon.

The workflow includes:

1. Subsetting daily ROMS NetCDF files to extract surface temperature across a subregion of the ROMS domain
2. Aggregating daily data into annual files while handling duplicate and missing records
3. Processing the annual files in R to perform spatial analysis by NMFS management areas
4. Calculate the MHWI

*NOTE:* For now we are only doing the hindcast. When we move to projections we will need to add the bias correction.

## Prerequisites

### Software Requirements on loon
- Access to loon
- Bash shell environment
- CDO ([Climate Data Operators](https://code.mpimet.mpg.de/projects/cdo))

### Required Data Files
- ROMS NetCDF output files
- NEP grid file (`NEP_grid_5a.nc`)
- NMFS management area shapefiles (in `data/NMFS management area shapefiles/gf95_nmfs.shp`)

## Processing Pipeline

### Step 1: Extract Surface Temperature Data

The first script extracts surface temperature data from the ROMS model output. It also subsets the domain to a smaller grid based on values of `xi_rho` and `eta_rho`, as determined in the script `nep_domain_subsetting.R`.

```bash
# Create output directory
mkdir -p ./surface_temp_subset
# Process each file from the list
while read file_path; do
    # Extract filename without path
    filename=$(basename "$file_path")
    
    # Create output file name
    output_file="./surface_temp_subset/surf_temp_${filename}"
    
    # Extract temp variable at surface level (level 42 in s_rho)
    # With spatial subsetting using your specific indices
    cdo -f nc4 -z zip_9 selindexbox,43,226,215,464 -sellevidx,42 -selvar,temp "$file_path" "$output_file"
    
    echo "Processed $filename"
done < hind_files.txt
```

This script:
- Reads a list of ROMS NetCDF files from `hind_files.txt`. Producing this takes digging into loon to find the relevant daily files for each simulation.
- For each file, extracts the surface temperature (level 42 in the vertical dimension)
- Applies geographic subsetting using model grid indices (43-226, 215-464)
- Saves the resulting subset data to compressed NetCDF files

### Step 2: Aggregate to Annual Files

The script `combine_daily_to_annual.sh` processes the subset temperature files into annual compilations while handling issues like:
- Merging daily records that may span multiple files
- Indexing files by year to improve processing efficiency
- Detecting and handling duplicate timestamps
- Checking for missing days in each year
- Setting appropriate time axis formatting

This step creates standardized annual NetCDF files with daily time steps.

### Step 3: Spatial Analysis in R

Now I moved the annual NetCDF files to my local for development, but it can (should) all be done on loon instead. We need to move to R here because spatial joining (e.g. clipping to NMFS areas) can't be done in CDO.

The R scripts provide functionality to:
1. Load the ROMS grid information and transform coordinates
2. Apply the NMFS management area spatial mask
3. Process each annual NetCDF file to calculate mean temperatures by NMFS area
4. Filter by maximum depth to focus on relevant ocean regions

The `process_annual_nc()` function performs the following steps:
- Opens a specified NetCDF file
- Extracts temperature data
- Matches with ROMS grid coordinates
- Filters out land cells and areas deeper than the specified maximum depth
- Clips to specified NMFS areas (610, 620, 630)
- Calculates daily means by NMFS area
- Converts time steps to calendar dates

## Usage

### Subsetting daily files on loon
```bash
# Make sure hind_files.txt contains paths to your ROMS files
bash pull_sst.sh
```

### Creating annual files on loon
```bash
bash combine_daily_to_annual.sh
```

### Spatial matching and averaging within NMFS areas in R
```r
# In R
source("annual_nc_functions.R")
# Process annual netCDF files with a maximum depth of 1000m
daily_sst_ls <- lapply(nc_files, process_annual_nc, maxdepth = 1000)
```

## Bias correction with delta method

To add when we do projections. What is the spatial and temporal scale at which the correction should occur?

## Calculate MHWI

XXX

## Notes

- The codebase specifically focuses on NMFS areas 610, 620, and 630
- The maximum depth parameter can be adjusted to focus on different depth ranges (1000 vs 300 to match our previous approaches)
- The process handles leap years and partial years correctly
- A reference index is created to speed up processing when running multiple times
- The approach takes mean temperatures by NMFS area and then calculates the MHWI. Should it instead calculate the MHWI at grid cell level and then average?

## Contact

Alberto Rovellini
arovel@uw.edu
