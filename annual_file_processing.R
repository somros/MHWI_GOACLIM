library(tidync)
library(ncdf4)
library(tidyverse)
library(sf)

select <- dplyr::select

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
  filter(between(xi_rho,43,226), between(eta_rho,215,464)) %>%
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

# open netcdf file to process
# this will be part of the function
tempfile <- here::here('data','hindcast_sst', 'annual_2000.nc')
temp <- tidync(tempfile)
temp_vars <- hyper_grids(temp) %>% # all available grids in the ROMS ncdf
  pluck("grid") %>% # for each grid, pull out all the variables asssociated with that grid and make a reference table
  purrr::map_df(function(x){
    temp %>% activate(x) %>% hyper_vars() %>% 
      mutate(grd=x)
  })

temp_rhogrd <- temp_vars %>% filter(name=="temp") %>% pluck('grd')
temp_rho <- temp %>% activate(temp_rhogrd) %>% hyper_tibble(na.rm = F) %>%
  dplyr::select(xi_rho,eta_rho,temp,ocean_time)

# we need to figure out if the NA values are on land or what else is happening
# match grid to netcdf files
temp_rho <- roms_rho %>%
  full_join(temp_rho, by = c("xi_rho","eta_rho"))

# # at this point there are a lot of NA values for temp
# # when you plot them, you can actually see that these all correspond to land
# # so this is the land mask from the ROMS model and these NAs can safely be discarded
# # check na
# temp_na <- temp_rho[is.na(temp_rho$temp),]
# # view
# temp_na %>%
#   filter(ocean_time == 1) %>%
#   ggplot()+
#   geom_sf()

# drop nas
temp_rho <- temp_rho %>% drop_na(temp)

# subset to h < 1000
temp_rho <- temp_rho %>%
  filter(h <= 1000) # to do: make this an argument for the function, may be 1000 or 300

# view
# temp_rho %>%
#   filter(ocean_time == 1) %>%
#   ggplot()+
#   geom_sf(aes(color = temp))
# spatial parsing seems to have worked OK

# clip to nmfs areas mask
temp_nmfs <- temp_rho %>%
  st_join(mask) %>%
  filter(NMFS_AREA %in% c(610,620,630))
  
# map
# temp_nmfs %>%
#   filter(ocean_time == 1) %>%
#   ggplot()+
#   geom_sf(aes(color = NMFS_AREA))

# TODO: we no longer need the spatial information so drop it for simplicity
# ...

# average by day and nmfs area
temp_day <- temp_nmfs %>%
  group_by(ocean_time, NMFS_AREA) %>%
  summarise(temp = mean(temp))

# save into list
# merge into one long series across years
