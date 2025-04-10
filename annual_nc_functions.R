#' Process annual netCDF files for temperature data
#'
#' This function processes ROMS netCDF files containing temperature data,
#' filters by maximum depth, and calculates average temperatures by NMFS area.
#'
#' @param ncfile Character string. Name of the netCDF file to process.
#'   The file should be located in the 'data/hindcast_sst' directory.
#' @param maxdepth Numeric. Maximum depth in meters to include in the analysis.
#'   Areas deeper than this value will be filtered out.
#'
#' @return A data frame with three columns:
#'   \item{NMFS_AREA}{NMFS area code (610, 620, or 630)}
#'   \item{temp}{Mean temperature for each area and date}
#'   \item{date}{Date in POSIXct format}
#'
#' @details
#' The function performs several steps:
#' 1. Opens the specified netCDF file
#' 2. Extracts temperature data on the rho grid
#' 3. Matches with the ROMS grid coordinates
#' 4. Filters out land cells (NA values)
#' 5. Subsets data to areas shallower than maxdepth
#' 6. Clips to specified NMFS areas (610, 620, 630)
#' 7. Calculates daily means by NMFS area
#' 8. Converts time steps to calendar dates
#'
#' @note Requires pre-loaded objects: roms_rho, mask
#'
#' @import tidync
#' @import dplyr
#' @import sf
#' @import ncdf4
#' @import lubridate
#' @importFrom here here
#' @importFrom purrr pluck map_df
#' @importFrom tidyr drop_na
#'
#' @examples
#' # Process a specific netCDF file with a maximum depth of 1000m
#' temp_data <- process_annual_nc("sst_2010.nc", 1000)
#'
#' # Plot the resulting data
#' library(ggplot2)
#' ggplot(temp_data, aes(x = date, y = temp, color = factor(NMFS_AREA))) +
#'   geom_line() +
#'   labs(title = "Mean temperature by NMFS area", color = "NMFS Area")
process_annual_nc <- function(ncfile, maxdepth) {
  
  print(paste("Processing file ", ncfile))
  
  # Open netCDF file to process
  tempfile <- here::here('data', 'hindcast_sst', ncfile)
  temp <- tidync(tempfile)
  temp_vars <- hyper_grids(temp) %>% # All available grids in the ROMS ncdf
    pluck("grid") %>% # For each grid, pull out all the variables associated with that grid
    purrr::map_df(function(x) {
      temp %>% activate(x) %>% hyper_vars() %>% 
        mutate(grd = x)
    })
  
  temp_rhogrd <- temp_vars %>% filter(name == "temp") %>% pluck('grd')
  temp_rho <- temp %>% activate(temp_rhogrd) %>% hyper_tibble(na.rm = FALSE) %>%
    dplyr::select(xi_rho, eta_rho, temp, ocean_time)
  
  # NB: the default in hyper_tibble() is na.rm = T. 
  # Setting it to F reads in many NA values of temperature that correspond to ROMS cells on land
  # We need to read them in to ensure correct matching with xi and eta from the grid file
  
  # Match grid to netCDF files
  temp_rho <- roms_rho %>%
    full_join(temp_rho, by = c("xi_rho", "eta_rho"))
  
  # Drop NAs (land cells)
  temp_rho <- temp_rho %>% drop_na(temp)
  
  # Subset to areas shallower than maxdepth
  temp_rho <- temp_rho %>%
    filter(h <= maxdepth)
  
  # Clip to NMFS areas mask
  # This is the slowest step in the process
  temp_nmfs <- temp_rho %>%
    st_join(mask) %>%
    filter(NMFS_AREA %in% c(610, 620, 630))
  
  # Drop the spatial information as it's no longer needed
  temp_nmfs <- temp_nmfs %>%
    st_drop_geometry() %>%
    select(ocean_time, NMFS_AREA, temp)
  
  # Average by day and NMFS area
  temp_day <- temp_nmfs %>%
    #group_by(ocean_time, NMFS_AREA) %>%
    group_by(ocean_time) %>%
    summarise(temp = mean(temp), .groups = "drop")
  
  # Handle time steps
  nc <- nc_open(tempfile)
  
  # Read the time variables
  time_data <- ncvar_get(nc, "ocean_time")
  
  # Get time attributes
  time_units <- ncatt_get(nc, "ocean_time", "units")$value
  time_calendar <- ncatt_get(nc, "ocean_time", "calendar")$value
  
  # Parse the units string to get reference time
  time_parts <- strsplit(time_units, " ")[[1]]
  ref_date_str <- paste(time_parts[3:length(time_parts)], collapse = " ")

  # Convert the numeric values to dates
  dates <- data.frame("ocean_time" = time_data,
                      "date" = as.POSIXct(time_data, origin = ref_date_str, tx = "UTC"))
  
  # Force the time to be at 12:00:00
  dates <- dates %>%
    mutate(date = update(date, hour = 12, minute = 0, second = 0))

  # Close the file
  nc_close(nc)
  
  # Add time to daily dataframe
  temp_day <- temp_day %>%
    left_join(dates, by = "ocean_time") %>%
    select(-ocean_time)
  
  return(temp_day)
}