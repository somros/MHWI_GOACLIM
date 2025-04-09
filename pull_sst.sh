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
