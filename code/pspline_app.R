library(shiny)
library(lubridate)
library(tsibble)
library(zoo) # for interpolations
library(plotly) # for interactive plots 
library(tidyverse)
library(magrittr)
library(pspline) # Added for sm.spline function

ui <- fluidPage(
  titlePanel("ROV Track Smoothing App"),
  
  sidebarLayout(
    sidebarPanel(
      # File input for navigation file
      fileInput("navigationFile", "Upload Navigation CSV File", # value = "C:/repos/BIIGLE-video-epifaunal-density-estimation/nav/Generic_navigation_generic.csv" , 
                accept = c(".csv")),
      
      # Slider for dfs parameter
      sliderInput("dfs", "Smoothing parameter (df) for smooth.spline:",
                  min = 3, max = 200 , value = 70, step = 1),
      
      # Checkbox to enable/disable dfs_pspline
      checkboxInput("usePspline", "Use pspline smoothing", value = TRUE),
      
      # Conditional panel that appears only when pspline is enabled
      conditionalPanel(
        condition = "input.usePspline == true",
        sliderInput("dfs_pspline", "Smoothing parameter (df) for pspline:",
                    min = 3, max = 200, value = 100, step = 1)
      ),
      
      # Action button to update plot
      actionButton("updatePlot", "Update Plot"),
      
      # Download button for smoothed data
      downloadButton("downloadData", "Download Smoothed Data")
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Plot", plotlyOutput("trackPlot")),
        tabPanel("Data Preview", dataTableOutput("dataTable"))
      )
    )
  )
)

server <- function(input, output, session) {
  # Reactive value to store the navigation data
  navigationData <- reactiveVal(NULL)
  
  # Process uploaded file
  observeEvent(input$navigationFile, {
    req(input$navigationFile)
    
    navigation <- read_csv(input$navigationFile$datapath)
    navigationData(navigation)
    
    # Display message
    showNotification("Navigation data loaded successfully!", type = "message")
  })
  
  # Function to process the data and create smoothed tracks
  processedData <- eventReactive(input$updatePlot, {
    req(navigationData())
    #datetime
    # Copy from your original script with modifications
    positions <- navigationData()
    
    # Check if datetime column exists
    if("datetime" %in% colnames(positions)) {
      # Check and convert datetime if necessary
      if(!inherits(positions$datetime, c("POSIXct", "POSIXt"))) {
        positions %>%  mutate( datetime = dmy_hms(datetime)) -> positions
      }
    } else {
      # If datetime doesn't exist, try to create it from date and time columns
      if(all(c("date", "time") %in% colnames(positions))) {
        positions %>%  mutate( datetime = dmy_hms(datetime)) -> positions
      } else {
        showNotification("No datetime column found and couldn't create one!", type = "error")
        return(NULL)
      }
    }
    
    # Make a time column of elapsed seconds
    positions$elapsed_seconds <- as.numeric(difftime(positions$datetime, positions$datetime[1], units = "secs"))
    
    # Create missing timestamps and interpolate
    tryCatch({
      positions <- positions %>%
        select(datetime, any_of(c("videotime", "lon", "lat", "depth", "elapsed_seconds"))) %>%
        add_row(., datetime = .$datetime[1] + 1, .before = 2) %>%
        as_tsibble(index = datetime) %>%
        fill_gaps() %>%
        as_tibble()
      
      # Determine which columns to interpolate
      cols_to_interpolate <- intersect(c("lon", "lat", "depth", "elapsed_seconds"), colnames(positions))
      
      # Interpolate values
      for(col in cols_to_interpolate) {
        new_col_name <- paste0(toupper(col), "2")
        positions[[new_col_name]] <- zoo::na.approx(as.vector(positions[[col]]))
      }
      
      # Check for NAs in key columns
      if(any(is.na(positions$LON2)) | any(is.na(positions$LAT2)) | any(is.na(positions$DEPTH2))) {
        showNotification("Warning: There are NA values in interpolated coordinates", type = "warning")
      }
      
      # Smooth the track
      t <- 1:nrow(positions)
      x <- positions$LON2
      y <- positions$LAT2
      
      # Get smoothing parameters from input
      dfs <- input$dfs
      
      # Fit smoothing splines
      sx <- smooth.spline(t, x, df = dfs)
      sy <- smooth.spline(t, y, df = dfs)
      
      # Apply pspline if selected
      if(input$usePspline) {
        dfs_pspline <- input$dfs_pspline
        sxp <- sm.spline(t, x, df = dfs_pspline)
        syp <- sm.spline(t, y, df = dfs_pspline)
        
        # Add smoothed coordinates to positions dataframe
        positions$smooth_x_pspline <- sxp$ysmth
        positions$smooth_y_pspline <- syp$ysmth
      }
      
      # Add smoothed coordinates to positions dataframe
      positions$smooth_x <- sx$y
      positions$smooth_y <- sy$y
      
      return(list(
        positions = positions,
        x = x, y = y,
        sx = sx, sy = sy,
        sxp = if(input$usePspline) sxp else NULL,
        syp = if(input$usePspline) syp else NULL
      ))
      
    }, error = function(e) {
      showNotification(paste("Error in data processing:", e$message), type = "error")
      return(NULL)
    })
  })
  
  # Generate the plot
  output$trackPlot <- renderPlotly({
    req(processedData())
    
    data <- processedData()
    
    p <- plot_ly() %>% 
      add_trace(x = data$x, y = data$y, mode = "markers", type = "scatter", 
                name = "Un-smoothed", marker = list(size = 4, color = 'black')) %>%
      add_trace(x = data$sx$y, y = data$sy$y, mode = "lines", type = "scatter", 
                name = "Smoothed (smooth.spline)", line = list(color = 'darkred', width = 2))
    
    if(input$usePspline && !is.null(data$sxp)) {
      p <- p %>% add_trace(x = data$sxp$ysmth %>% as.vector(), 
                           y = data$syp$ysmth %>% as.vector(), 
                           mode = "lines", type = "scatter", 
                           name = "Smoothed (pspline)", 
                           line = list(color = 'orange', width = 2))
    }
    
    p %>% layout(title = "Difference of un-smoothed and smoothed ROV transect",
                 xaxis = list(title = "Longitude"),
                 yaxis = list(title = "Latitude"))
  })
  
  # Show data preview
  output$dataTable <- renderDataTable({
    req(processedData())
    processedData()$positions %>%
      select(datetime, any_of(c("LON2", "LAT2", "DEPTH2", "smooth_x", "smooth_y", 
                                "smooth_x_pspline", "smooth_y_pspline")))
  })
  
  # Download handler for smoothed data
  output$downloadData <- downloadHandler(
    filename = function() {
      paste("nav/smoothed_", input$navigationFile, ".csv", sep="")  
    },
    content = function(file) {
      req(processedData())
      write.csv(processedData()$positions, file, row.names = FALSE)
    }
  )
}

shinyApp(ui = ui, server = server)