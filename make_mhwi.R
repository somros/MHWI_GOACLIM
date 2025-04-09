# Alberto Rovellini
# Based on Anna Sulc's code
# First attmept

library(heatwaveR)
library(dplyr)
library(ggplot2)
library(foreach)
library(doParallel)

hindcast_sst <- readRDS(here::here("data","hindcast_nmfs_daily.RDS"))

# change date format
hindcast_sst <- hindcast_sst %>%
  mutate(t = as.Date(date))

###For grid/spatial data####

make_event <- function(df){
  clim <- ts2clm(data = df, 
                 x= t, 
                 y= temp, 
                 climatologyPeriod = c("1991-01-01", "2020-12-31"), 
                 pctile = 90)
  mhwi <- detect_event(data = clim)
  return(mhwi$event)
}


mhwi_nmfs <- hindcast_sst %>% 
  group_by(NMFS_AREA) %>% 
  #Run MHW detecting function for each group
  group_modify(~make_event(.x))


#Metrics to check
mhwi_nmfs %>% 
  dplyr::ungroup() %>%
  dplyr::select(NMFS_AREA,event_no, duration, date_start, date_peak, intensity_max, intensity_cumulative) %>% 
  dplyr::arrange(-intensity_max) %>% 
  print(n=30)

mhw_summary_by_year <- mhwi_nmfs %>%
  mutate(year_start = year(date_start)) %>%  
  group_by(NMFS_AREA, year_start) %>%
  summarise(
    num_events = n(),  
    avg_duration = mean(duration, na.rm = TRUE),  
    max_intensity = max(intensity_max, na.rm = TRUE), 
    mean_intensity = mean(intensity_mean, na.rm = TRUE),
    total_intensity = sum(intensity_cumulative, na.rm = TRUE)  
  ) %>%
  arrange(year_start) 

print(mhw_summary_by_year)

#Check the results
ggplot(mhw_summary_by_year, aes(x = year_start, y = total_intensity, color = factor(NMFS_AREA))) +
  geom_line() +
  geom_point() +
  labs(x = "Year", y = "Total Intensity", title = "Total Intensity of Heatwaves by Year") +
  theme_minimal()

ggplot(mhw_summary_by_year, aes(x = year_start, y = max_intensity, color = factor(NMFS_AREA))) +
  geom_line() +
  geom_point() +
  labs(x = "Year", y = "Max Intensity", title = "Max Intensity of Heatwaves by Year") +
  theme_minimal()

ggplot(mhw_summary_by_year, aes(x = year_start, y = mean_intensity, color = factor(NMFS_AREA))) +
  geom_line() +
  geom_point() +
  labs(x = "Year", y = "Mean Intensity", title = "Mean Intensity of Heatwaves by Year") +
  theme_minimal()


# this does not work with NMFS areas
event_line(mhwi_nmfs, spread = 180, metric = intensity_max, 
           start_date = "1991-01-01", end_date = "2020-12-31")

ggplot(mhwi_nmfs, aes(x = date_start, y = intensity_max)) +
  geom_lolli(colour = "salmon", colour_n = "red", n = 3) +
  # geom_text(colour = "black", aes(x = as.Date("2006-08-01"), y = 5,
  #                                 label = "The marine heatwaves\nTend to be left skewed in a\nGiven time series")) +
  labs(y = expression(paste("Max. intensity [", degree, "C]")), x = NULL)+
  facet_wrap(~NMFS_AREA)

