#!/bin/bash

# -------------------------------------------------------------------------
# Script to combine daily NetCDF files into annual files
# Processes ROMS simulation output with multiple daily records per NC file
# Handles files that straddle years and checks for duplicates/missing records
# -------------------------------------------------------------------------

# Directory containing NetCDF files
INPUT_DIR="./surface_temp_subset"
# Directory for output files
OUTPUT_DIR="./annual_files"
# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR

# Create index directory to speed up processing
INDEX_DIR="./year_index"
mkdir -p $INDEX_DIR

# Years to process (1990-2020)
START_YEAR=1990
END_YEAR=2020

# Only create the index if it doesn't exist yet (saves time on re-runs)
if [ ! -f "$INDEX_DIR/indexed" ]; then
  echo "Creating year-to-file index (this will speed up future runs)..."
  
  for YEAR in $(seq $START_YEAR $END_YEAR); do
    > $INDEX_DIR/files_${YEAR}.txt
  done
  
  # Process all files once to build the index
  for NCFILE in $INPUT_DIR/surf_temp_*.nc; do
    BASENAME=$(basename $NCFILE)
    echo "Indexing $BASENAME..."
    
    # Get years in this file (do this only once to avoid calling cdo multiple times)
    YEARS=$(cdo showtimestamp $NCFILE | grep -o '[0-9]\{4\}' | sort | uniq)
    
    # Handle files containing "hind03" differently for years 2011-2013
    # These files contain duplicate records with very low temperatures
    # We exclude them at the indexing stage because mergetime keeps the first record by default
    # But we need to be careful with files that straddle years (contain data for multiple years)
    SKIP_YEARS=""
    if [[ "$BASENAME" == *"hind03"* ]]; then
      for YEAR in $YEARS; do
        if [ $YEAR -ge 2011 ] && [ $YEAR -le 2013 ]; then
          # Mark this year to be skipped, but don't skip the entire file
          SKIP_YEARS="$SKIP_YEARS $YEAR"
          echo "Will exclude $BASENAME from indexing for year $YEAR (contains problematic temperature records)"
        fi
      done
    fi
    
    # Add this file to the index for each year it contains
    # But skip specific years for hind03 files that we marked for exclusion
    for YEAR in $YEARS; do
      if [ $YEAR -ge $START_YEAR ] && [ $YEAR -le $END_YEAR ]; then
        # Check if this year should be skipped for this file
        SKIP=0
        for SKIP_YEAR in $SKIP_YEARS; do
          if [ "$YEAR" -eq "$SKIP_YEAR" ]; then
            SKIP=1
            break
          fi
        done
        
        if [ $SKIP -eq 0 ]; then
          echo "$NCFILE" >> $INDEX_DIR/files_${YEAR}.txt
        else
          echo "Excluding $BASENAME from index for year $YEAR"
        fi
      fi
    done
  done
  
  # Mark indexing as complete
  touch $INDEX_DIR/indexed
  echo "Indexing complete."
fi

# Process each year
for YEAR in $(seq $START_YEAR $END_YEAR); do
  echo "Processing year $YEAR..."
  
  # Create a temporary directory for this year's extracted files
  TEMP_DIR="./temp_${YEAR}"
  mkdir -p $TEMP_DIR
  
  # Check if we have any files indexed for this year
  if [ ! -s $INDEX_DIR/files_${YEAR}.txt ]; then
    echo "No files contain data for year $YEAR."
    continue
  fi
  
  # Process only files that contain data for this year (from our index)
  for NCFILE in $(cat $INDEX_DIR/files_${YEAR}.txt); do
    BASENAME=$(basename $NCFILE)
    cdo seldate,$YEAR-01-01,$YEAR-12-31 $NCFILE $TEMP_DIR/${YEAR}_${BASENAME}
  done
  
  # Check if we extracted any files for this year
  if [ "$(ls -A $TEMP_DIR)" ]; then
    echo "Merging files for $YEAR..."
        export SKIP_SAME_TIME=1
    cdo mergetime $TEMP_DIR/${YEAR}_*.nc $TEMP_DIR/merged_${YEAR}.nc
    
    # Check for duplicate timestamps
    echo "Checking for duplicate timestamps in year $YEAR..."
    # Get actual number of timesteps directly from the file
    NUM_ACTUAL=$(cdo ntime $TEMP_DIR/merged_${YEAR}.nc)
    # Process timestamps more robustly by extracting just the dates with grep
    # and counting unique occurrences
    UNIQUE_DATES=$(cdo showtimestamp $TEMP_DIR/merged_${YEAR}.nc | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | sort | uniq | wc -l)
    
    if [ $NUM_ACTUAL -ne $UNIQUE_DATES ]; then
      echo "WARNING: Found $(($NUM_ACTUAL - $UNIQUE_DATES)) duplicate dates in year $YEAR!"
      # Log the duplicate dates
      echo "=== Duplicate dates in $YEAR ===" > $OUTPUT_DIR/duplicates_${YEAR}.log
      cdo showtimestamp $TEMP_DIR/merged_${YEAR}.nc | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | sort | uniq -c | awk '$1 > 1 {print $2 " appears " $1 " times"}' >> $OUTPUT_DIR/duplicates_${YEAR}.log
      echo "Duplicate dates logged to $OUTPUT_DIR/duplicates_${YEAR}.log"
    else
      echo "No duplicate dates found in year $YEAR."
                                                                                                                                                                                                          
    fi
    
    # Copy the merged file to output without modifying the time axis
    cp $TEMP_DIR/merged_${YEAR}.nc $OUTPUT_DIR/annual_${YEAR}.nc
    
    # Check for missing days compared to expected days in the year
    echo "Checking for missing days in year $YEAR..."
    # Calculate expected days in year (accounting for leap years)
    DAYS_IN_YEAR=$(if [ $(($YEAR % 4)) -eq 0 ] && [ $(($YEAR % 100)) -ne 0 ] || [ $(($YEAR % 400)) -eq 0 ]; then echo 366; else echo 365; fi)
    
    # Use CDO's built-in function to count timesteps (more reliable)
    FOUND_DAYS=$(cdo ntime $OUTPUT_DIR/annual_${YEAR}.nc)
    
    if [ "$FOUND_DAYS" != "$DAYS_IN_YEAR" ]; then
      # This is expected for partial years like 1990 starting in February
      echo "NOTE: Year $YEAR has $FOUND_DAYS days instead of $DAYS_IN_YEAR ($(($DAYS_IN_YEAR - $FOUND_DAYS)) missing)."
      
      # Create a list of all dates in the year
      > $TEMP_DIR/all_dates.txt
      START_DATE="$YEAR-01-01"
      for i in $(seq 0 $(($DAYS_IN_YEAR - 1))); do
        date -d "$START_DATE + $i days" +%Y-%m-%d >> $TEMP_DIR/all_dates.txt
      done
      
      # Create a list of dates present in the file
      cdo showtimestamp $OUTPUT_DIR/annual_${YEAR}.nc | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | sort > $TEMP_DIR/present_dates.txt
      
      # Find the missing dates
      echo "=== Missing dates in $YEAR ===" > $OUTPUT_DIR/missing_${YEAR}.log
      comm -23 $TEMP_DIR/all_dates.txt $TEMP_DIR/present_dates.txt >> $OUTPUT_DIR/missing_${YEAR}.log
      echo "Missing dates logged to $OUTPUT_DIR/missing_${YEAR}.log"
      
      # For first and last years of the series, this is normal
      if [ $YEAR -eq $START_YEAR ] || [ $YEAR -eq $END_YEAR ]; then
        echo "This is expected for the first or last year of the series."
      else
        echo "WARNING: This is not a boundary year and should have complete data!"
      fi
      
      # Save the available timestamps to a reference file
      cdo showtimestamp $OUTPUT_DIR/annual_${YEAR}.nc > $OUTPUT_DIR/dates_${YEAR}.txt
      echo "Available dates listed in $OUTPUT_DIR/dates_${YEAR}.txt for reference"
    else
      echo "All $DAYS_IN_YEAR days present for year $YEAR."
    fi
    
  else
    echo "No data found for year $YEAR after extraction!"
  fi
  
  # Clean up temporary directory
  rm -rf $TEMP_DIR
done

echo "Processing complete. Annual NetCDF files are in $OUTPUT_DIR/"
