# BIIGLE-video-epifaunal-density-estimation .- BVides -

We present a method to calculate epifaunal (binned) species abundance and density along video transects, calculating a strip transect of seabed area (transect length * transect width) derived from geographic position and video data.

[![DOI](https://sandbox.zenodo.org/badge/947373666.svg)](https://handle.stage.datacite.org/10.5072/zenodo.293672)

**Input: ** There are two input files needed for the scripts to run.
1) annotations (csv.): this is the standard Biigle Video annotations csv file with 1-frames annotations ( tracked annotation will not work) and lasers marked regularly, whereas each dot was marked individually using the "point annotation tool".
2) navigation (csv.): Following data needs to be extracted from the raw data derived from the (ROV) GPS transponder: with time in real-world, time in video, geographic coordinates and depth 8all mandatory) and additionally pitch, roll, yaw, and camera parameters (focal length, sensor size, etc.) can be included but are not being processed- this is the standard Biigle Video navigation csv file with 1-frame navigation data and lasers marked regularly

|  datetime| video time | lat | long | depth | other metadata |
| :---: | :---: | :---: | :---: | :---: | :---: |
| dmy_hms | hms | dec.deg | dec.deg | (-)meters | XXX |
| dmy_hms | hms | dec.deg | dec.deg | (-)meters | XXX | 

Pre-processing of the navigation data can be achieved by selecting relevant data described above, and replace their column names to match the required names in the script: 

***replace the column names here ***
names(your_raw_navigation)[1:6] <- c("datetime","depth","heading","lon","lat", "videotime")

**notes**: make sure time columns in your raw data are all in the same time-zones or let R assume they are UTC/your local time zone

***Description of workflow (NOTE: the order of script applied has to be followed chronically !!!)***

***Step 1) arrange BIIGLE annotations *** 
Processes the BIIGLE annotation csv. report to sort any annotations chronically by time in video, represented by chronically order of “frames” column. 
This ensures that “frames” and thus time in video is the regulating column for arranging any annotations and not as observed initially, the column “created_at”.  

***Step 2) smoothing navigation data*** 
Processes the navigation, to firstly create missing datapoints to 1 second frequency by basic interpolation (with "na.approx"  function of the "zoo" package). 
Secondly, we chose to fit a cubic smoothing spline (stats::smooth.spline function) to the longitude and latitude data. Depth is not smoothed since it was considered to be precise enough.
WARNING: The resulting smoothed curve of longitude and latitude positions can be varying, depending which fitting method is used. 
Choice of numerical values for smoothing is highly dependent on the desired outcome of the analysis.
To fit the cubic smoothing spline, one can 1) set the numerical smoothing parameter df, spar or lamda by own choice 
OR 2) let the model compute the smoothing parameter objectively by ordinary leave-one-out or generalized’ cross-validation (GCV), so that one do not need to find smoothing parameters on their own.
Resulting smoothed latitude and longitude vectors can be assessed via the computed cross validation score, depending on cross-validation method applied above.  
Further explanation are given in the script.
ALTERNATIVE: Smoothing can be completely omitted if desired, in this case one needs to drop the code chunck where smoothing is applied and additionally active codelines at the end of step 2 (codeline 230), for further description see script 2.

***Step 3) Biigle video laser calibration*** 
Processes the arranged BIIGLE annotation file, to extract regular laser annotation (here every 10 seconds) for scaling image width and convert to seabed strip transect width.
Firstly, one has to specify image properties like resolution (image height and width in pixels, and calculated numbers of pixels) of the (ROV) camera used and the physical scale between the laser points in meters is needed. 
Example: The provided annotations are generated from HD videos, so HD image properties are embedded in the code. In the provided example, the physical laser scale is set to 0.075 m.
The BIIGLE annotation report is applied to filter out framegrabs of the “label name” annotation that was defined as “laser points”, here usually every 10 seconds. 
Framegrabs are only selected if there are two individual laser point annotation within one frame. The BIIGLE function tracked annotations will not work for this laser scaling approach. 
In the BIIGLE annotation csv. reports in general, each point annotation in a framegrab gets two specific framegrab point coordinates, supplied through the column "points"" of the BIIGLE annotation report .csv file. 
This information is then being used to calculate the laser scale distance in pixels between the two laser point coordinates in the selected framegrab using the dist() function of the stats package, which by default is the Euclidean distance.
Next, the ratio between the physical laser scale distance (derived from the image properties described above) to all the frame grab pixel laser scale distances gives the transformer laser scale distance in meters (see codeline 1289:
Framegrab laser scale (in meters) = physical laser scale distance (in meters) / framegrab laser scale distance (in pixels).
Consequently, the framegrab image width is calculated by multiplying the framegrab laser scale (in meters) with the image width in pixels (derived from the image properties described, 1920 pixels for HD videos)
The Y-dimension (image height) is not calibrated. Because the oblique angle of the (ROV) camera, the distance to the farther reach of the image is difficult to reliably measure with the 2-dot laser scale. Besides the visibility does not always allow the back of image to be exploited.
Thus we strongly advise not to use image height it to calculate the seabed area if oblique videos are applied.
The resulting width of view is then interpolated between the 10s measurements to match and further being joined to the frequency of the navigation (1s) with the “na.approx” function in the “zoo” package.

***Step 4) Biigle video 3D distance travelled*** 
Processes the interpolated smoothed navigation data to calculate the total distance travelled of the video strip transect. 
The total distance travelled is three-dimensional, by summing the 3D (latitude, longitude and depth) Euclidian distance between each points.
For calculating distances it is crucial to transform smoothed latitudes and longitudes in decimal degrees into a cartesian or projected coordinate system, e.g a UTM system with logged X (easting) and Y(northing) coordinates, which is done here by using the sf package (function "st_as_st()").  
UTM map projection is a favorable choice for analyzing spatial data since UTM units are displayed in meters, which makes it applicable for calculating distances, including depth distances.
Applying the "dist()" function of the R package stats whereas Euclidean distance is the default method, the three-dimensional distance (“distance_3d”) between successive  smoothed, interpolated Xs, smoothed interpolated Ys and the interpolated depths are calculated. 
To calculate the cumulated three-dimensional distance travelled, the function "cumsum" is applied to “distance_3”, and by using the function tail() and pull() the total three-dimensional distance travelled is printed. 
Lastly, the generated output, “distance_3D” and cumulated three-dimensional distance travelled columns are joined together with the seabed surface navigation data (from step 4), providing all crucial navigation data (seabed width, distance travelled) to calculate the video strip transect of seabed area, or ROV footprint in the final step 5.
ALTERNATIVE: In case the depth is desired to be ommited, the 2D distance travelled (including latitutde and longitude only) can be computed when adjusting the code by following: remove in codeline 117 "depth2 = depth" and rename in codeline 121 distance_3d to distance_2d. Codeline 123, adjust the matrix of distance_2d to: distance_2d = matrix(c(X2,Y2,X,Y), ncol = 2 ....
Exchange all 3ds with 2ds in codeline 136,138,148,153 and 156.
WARNING: In case when smoothing is not desired/ommitted in step 2, thus raw coordinates should be used to calculate the distance travelled, one need to replace in codeline 90  (coords =c("xsmoothed","ysmoothed")) with instead c("LON2","LAT2") (interpolated raw coordinates from navigation file) for transformation into UTM.



***Step 5) Analyzing BIIGLE Video Data*** 
The average image width over the whole track and 3D distance travelled are used the compute the footprint of the survey which in turn allows converting the raw abundance (number of objects annotated in Biigle) to density (ind.m-2) to quantify epibenthic megafauna in the whole transect. 
Further granularity is introduced by splitting the track into 50 m long bins into which the density of each species is calculated. In this case, note that the average width of view of each bin is used to calculate the surface area sampled in each bin).
In this example, the bin size is set to 50 m three dimensional distance travelled but users can change this input value, according to their own desired output.
First, 50 m bins are created based on the computed 3D distance travelled. Next, supporting metadata for each 50 m bin is calculated: mean bin depth and mean bin seabed width, both derived from the "mean()" function. Each bins surface is then calculated as following (codeline 85): bin  surface = mean width * bin size (of 50 m)
Next, the arranged BIIGLE annotations are loaded, and the frames column is used to allocate each annotation a start and end second, to join the arranged annotations with the nearest timestamp of the navigation data, creating a dataset of joined arranged BIIGLE annotations with selected parameters of smoothed and interpolated X, smoothed and interpolated Y,  interpolated depth, seabed width, date, time and bin. 
Now, the first final output is generated as bins species abundance. Species abundance per bin is calculated, by counting the number of all available annotations of each given (species) label from the “label_name” column and transformed into a pivot table.
The second final output is generated as species density in each bin. To do so, each bins species abundance previously calculated is divided by each bins seabed surface area calculated, providing species bin densities.
The third final output is calculation of species density along the total transect. To do so, first the total transect seabed surface is calculated from the total three-dimensional distance travelled multiplied with the average seabed width of the whole transect. Then total species abundance is taken from the bins species abundance table, only including the row “all” which is the cumulated sum of species abundance in each bin. 
Finally, total species density is calculated similar to bin species density, as followed: cumulated sum of bin species abundance divided by total transect seabed surface area.
