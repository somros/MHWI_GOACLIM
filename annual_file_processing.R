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
  mutate(lon_rho = lon_rho - 360) %>%
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

# run function over all nc files and save objects into a list
# this takes time
daily_sst_ls <- lapply(nc_files, process_annual_nc, maxdepth = 1000)

# merge into one data frame
daily_sst <- daily_sst_ls %>% bind_rows()

# save as RDS file
# XXX

# do MHWI processing in a separate script
