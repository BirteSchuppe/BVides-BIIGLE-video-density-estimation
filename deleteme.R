library(lubridate)
library(tsibble)
library(zoo) # for interpolations
library(plotly) # for interactive plots 
library(tidyverse)
library(magrittr)

getwd() -> wd
# delete the "code" part of the pathway so that the rest of the path are not relative to the code directory
wd <- str_remove(wd, "/code") 

# set the working directory to the directory above "code"
setwd(wd)


# list the csv tables and print their names
list.files(paste0( wd,"/nav"), pattern = ".csv$" ) %>% 
  # exclude the "arranged" pattern 
  str_subset("smoothed", negate = T)  %>%  paste0("\n avialable CSV tables: \n",.) %>% cat



# input
navigation_file <- "Generic_navigation_generic.csv"
dfs = 10
dfs_pspline = NULL



# run the code to make the plots

read_csv(paste0(wd,"/nav/",navigation_file) ) -> navigation

# fill the gaps in the shp file
# time management
navigation %>% 
  # make the time column - if you have a data and a time column
  mutate(datetime = datetime) -> positions
# if you have a dmy_hms character string


# check that datetime is a datetime object
# if class of datetime is not "POSIXct" or "POSIXt" then convert it
if(!class(positions$datetime)[1] %in% c("POSIXct", "POSIXt"))  {
  print("setting datetime to POSIXt")
  positions %>%  mutate( datetime = dmy_hms(datetime)) -> positions
}

# check that the time column is in the right format
positions %>% 
  select(datetime) %>% glimpse

# make a time column of elapsed seconds based on column datetime, in case for if videotime (logged via ROV system) is not starting at 0
positions$elapsed_seconds <- as.numeric(difftime(positions$datetime, positions$datetime[1],units = "secs"))


# create the missing time stamps so that you have a reading at each second 
positions %>%
  select(datetime, videotime,lon,lat, depth, elapsed_seconds ) %>% 
  add_row(. , datetime  = .$datetime[1] + 1  , .before = 2) %>% 
  as_tsibble(index = datetime) %>%
  fill_gaps() %>% # automatically creates the missing timestamps
  as_tibble() %>%
  # interpolate the coordinates values for the timestamps you have created
  # these wont be accurate but you will replace them soon
  # they are still a basic interpolation of the closest coordinates 
  mutate(LON2 = zoo::na.approx(as.vector(lon)),
         LAT2 = zoo::na.approx(as.vector(lat)), 
         DEPTH2 = zoo::na.approx(as.vector(depth)),
         VIDEOTIME2 = zoo::na.approx(as.vector(elapsed_seconds))           ) -> positions  
# note this might also be enough if your track look good

# check that there are no NA left in LON2 or LAT2 or DEPTH2
if(any(is.na(positions$LON2)) | any(is.na(positions$LAT2)) | any(is.na(positions$DEPTH2))) {
  print("There are NA values in LON2, LAT2 or DEPTH2")
} else {
  print("No NA values in LON2, LAT2 or DEPTH2. That's great")
}

# Smooth the track  
t <- 1:nrow(positions)
x <- positions$LON2
y <- positions$LAT2
# z  # no smoothing of th ~DEPTH: interpolation should be enough 
# Fit a cubic smoothing spline to each dimension
# !!! this is user input. You can decide on the right smoothing parameter after checking the plot below


sx <- smooth.spline(t, x, df = dfs, spar = spars, cv = TRUE)
sy <- smooth.spline(t, y, df = dfs, spar = spars, cv = TRUE)


# applying pspline from the pspline package 
# if dfsplines are not specified, dont input it 
if(!exists("dfs_pspline")) {
  sxp <-  sm.spline(t, x, df = dfs_pspline ) # 
  syp <-  sm.spline(t, y, df = dfs_pspline ) #, df = 10 
}else{
  sxp <-  sm.spline(t, x, , df = 100 ) # , df = 10
  syp <-  sm.spline(t, y , df = 100  ) #, df = 10 
  
}


# plot the recorded tracks 
plot(x,y, cex = 0.25, col = "black", main = paste0("Difference of un-smoothed and smoothed ROV transect "))
# overlay the smoothed track
lines(sx[[2]], sy[[2]], col = "darkred", lwd = 2)
# lines for psplines 
lines(sxp$ysmth, syp$ysmth, col = "orange", lwd = 2)

legend("topleft", legend=c("smoothed", "un-smoothed", "smoothed pspline"),
       col=c("darkred", "black", "orange"), lty=1:2, cex=0.8)

 
# put all 3 lines in a plotly scatterplot 
plot_ly() %>% 
  add_trace(x = x, y = y, mode = "markers", type = "scatter", name = "un-smoothed", marker = list(size = 4)) %>%
  add_trace(x = sx[[2]], y = sy[[2]], mode = "lines", type = "scatter", name = "smoothed") %>%
  add_trace(x = sxp$ysmth %>%  as.vector() , y = syp$ysmth %>%  as.vector(), mode = "lines", type = "scatter", name = "smoothed pspline") %>%
  layout(title = "Difference of un-smoothed and smoothed ROV transect",
         xaxis = list(title = "Longitude"),
         yaxis = list(title = "Latitude"))



