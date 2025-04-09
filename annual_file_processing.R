# Alberto Rovellini
# 04/09/2025
# This script takes annual NetCDF files of SST, maps them to NMFS areas 610-630, and calculates daily mean SST
# For now this works on the ROMS hindcast only, which we should use for testing
# Still unanswered if it would be meaningful to do it for the projections

# NOTE: this script takes time to run. Subsetting the NC files helps (we could not do this otherwise), but the spatial joining to the NMFS area shapefile still is computation intensive. 
# It seems to take a couple of minutes per year.
# Ultimately this should be moved to loon and parallelized like the rest of the ROMS extraction code

library(tidync)
library(ncdf4)
library(tidyverse)
library(sf)
library(lubridate)

select <- dplyr::select

source("annual_nc_functions.R")

# list netcdf files containing sst
# hindcast only for now
nc_files <- list.files(here::here("data","hindcast_sst"))

# open grid 
# cell lat/lons from ROMS
romsfile <- here::here('data','NEP_grid_5a.nc')
roms <- tidync(romsfile)
roms_vars <- hyper_grids(roms) %>% # all available grids in the ROMS ncdf
  pluck("grid") %>% # for each grid, pull out all the variables asssociated with that grid and make a reference table
  purrr::map_df(function(x){
    roms %>% activate(x) %>% hyper_vars() %>% 
      mutate(grd=x)
  })

latlon_rhogrd <- roms_vars %>% filter(name=="lat_rho") %>% pluck('grd')
roms_rho <- roms %>% activate(latlon_rhogrd) %>% hyper_tibble() %>%
  dplyr::select(lon_rho,lat_rho,xi_rho,eta_rho,h) %>% 
  mutate(lon_rho = lon_rho - 360) %>% # flip ROMS lon coordinates to better match other spatial files
  st_as_sf(coords=c('lon_rho','lat_rho'),crs=4326)

# subset grid with the same indices as used for the nc files
roms_rho <- roms_rho %>%
  filter(between(xi_rho,43,226), between(eta_rho,215,464)) %>% # make sure you use the same indices as the ROMS data subsetting on loon
  mutate(xi_rho = (xi_rho - min(xi_rho)+1),
         eta_rho = (eta_rho - min(eta_rho)+1))

# open nmfs area mask
## Read in shape files of desired area.
mask <- st_read("data/NMFS management area shapefiles/gf95_nmfs.shp")

# subset to NMFS areas of interest
mask <- mask %>% filter(NMFS_AREA %in% c(610,620,630,640,650))%>% # subset to 610-650
  filter(GF95_NMFS1 %in% c(186,194,259,585,870)) %>% # Removes inter-coastal in SE AK
  select(NMFS_AREA, AREA)  %>%# area here seems to be in m2
  st_transform(crs = 4326)

# ##################################
# # DO NOT RUN
# # run function over all nc files and save objects into a list
# daily_sst_ls <- lapply(nc_files, process_annual_nc, maxdepth = 1000)
# 
# # merge into one data frame
# daily_sst <- daily_sst_ls %>% bind_rows()
# 
# # view
# daily_sst %>%
#   ggplot(aes(x = date, y = temp, color = factor(NMFS_AREA)))+
#   geom_line()
# 
# # save as RDS file
# saveRDS(daily_sst, "data/hindcast_nmfs_daily.RDS")
##################################
