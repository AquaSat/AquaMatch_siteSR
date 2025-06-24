#' @title Check to see if point is completely contained within path-row
#' 
#' @description
#' Using a set of points with lat/lon, and the unique pathrows associated with them,
#' add WRS pathrow information to the locations file, remove buffered points that
#' are not completely within the path row geometry. Buffer is defined in the yaml file.
#' 
#' @param WRS_pathrows list of pathrows to iterate over
#' @param locations dataframe of location
#' @param yaml contents of the yaml .csv file
#' 
#' @returns returns a dataframe of points and buffer that are fully contained by
#' a single pathrow with the id/lat/lon/PR information
#' 
#' @note
#' This step will result in more rows than the locations file, because a single 
#' location in space can fall into multiple pathrows.
#' 
#' 
check_for_containment <- function(WRS_pathrow, locations, yaml) {
  # get the WRS2 shapefile
  WRS <- read_sf("5_determine_RS_visibility/in/WRS2_descending.shp")
  # make locations into a {sf} object
  locs <- st_as_sf(locations, 
                   coords = c("Longitude", "Latitude"), 
                   crs = yaml$location_crs)
  # map over each path-row, adding the pathrow to the site. Note, this will create
  # a larger number of rows than the upstream file, because sites can be in more
  # than one pathrow. 
  # filter for one path-row
  one_PR <- WRS %>% filter(WRSPR == WRS_pathrow) 
  # get the locs that intersect the path-row
  x <- locs[one_PR, ]
  
  # buffer the location to make sure the AOI is completely within the PR
  x_buffd <- st_buffer(x, dist = as.numeric(yaml$site_buffer)) %>% 
    st_make_valid()
  # see if the buffered points are completely contained  
  is_contained_by_WRS = as_tibble(st_within(x_buffd,
                                            one_PR,
                                            sparse = FALSE)) %>% 
    rename(is_contained_by_WRS = V1)
  # and bind cols
  bind_cols(x, is_contained_by_WRS) %>% 
    st_drop_geometry() %>% 
    # only select the points completely contained by the WRS
    filter(is_contained_by_WRS == TRUE) %>% 
    # just to get lat/lon back
    left_join(., locations) %>% 
    select(id, Latitude, Longitude) %>% 
    mutate(WRSPR = WRS_pathrow)
}