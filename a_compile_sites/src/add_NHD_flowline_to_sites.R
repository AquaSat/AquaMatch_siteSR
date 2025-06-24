#' @title Locate the closest flowline to a site and measure distance
#' 
#' @description
#' Given a site that is geolocated, find the nearest NHDPlusHR flowline, assign
#' the permanent_identifier to the site and measure the distance to the flowline
#' assigning that distance to the site as well
#' 
#' @param sites_with_huc a spatial feature object of sites that have a huc assigned
#' for spatial subsetting
#' @param huc4 4-digit character string to filter sites by
#' @param GEE_buffer numeric value of buffer for GEE site extraction in meters
#' 
#' @returns a list containing dataframe of the spatial feature information with flowline and 
#' distance to flowline assignment as well as a dataframe of the number of intersections
#' 
#' 
add_NHD_flowline_to_sites <- function(sites_with_huc, 
                                      huc4,
                                      GEE_buffer) {
  
  message(paste0("Assigning NHD HR flowlines to sites within ", huc4))
  
  tryCatch({
    
    # filter sites for those in a single huc4
    sf_subset <- sites_with_huc %>%
      filter(str_sub(HUCEightDigitCode, 1, 4) == huc4) 
    
    # if huc4 < 1900 (conus points), we can use nhdplustools, otherwise we have to 
    # download from the national map.
    
    if (as.numeric(huc4) < 1900) {
      
      # get the aoi of the huc for grabbing flowlines
      huc4_aoi <- get_huc(id = huc4, type = "huc04")
      
      # get the flowlines in the huc
      huc4_fl <- get_nhdplus(AOI = huc4_aoi, realization = "flowline") %>%
        filter(grepl("stream|river|artificial", ftype, ignore.case = T)) %>% 
        select(fl_nhd_id = comid, 
               fl_gnis_id = gnis_id, 
               fl_gnis_name = gnis_name, 
               fl_fcode = fcode,
               fl_stream_order = streamorde) %>%
        # add column to merge after st_intersects()
        rowid_to_column("fl_id") %>% 
        mutate(fl_nhd_source = "NHDPlusv2",
               fl_nhd_id = as.character(fl_nhd_id))
      
    } else {
      
      # if huc4 >= 1900, process differently, as nhdtools fl is limited to CONUS
      
      # make sure the geopackage hasn't already been downloaded
      if (!file.exists(file.path("a_compile_sites/nhd/",
                                 paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")))) {
        
        # but if it isn't, download it!
        
        # set timeout so that... this doesn't timeout
        options(timeout = 60000)
        
        # url for the NHD Best Resolution for HUC4
        url = paste0("https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHD/HU4/GPKG/NHD_H_", huc4, "_HU4_GPKG.zip")
        download.file(url, destfile = file.path("a_compile_sites/nhd/", 
                                                paste0(huc4, ".zip")))
        
        unzip(file.path("a_compile_sites/nhd/", 
                        paste0(huc4, ".zip")), 
              exdir = "a_compile_sites/nhd/")
        
        # remove zip
        unlink(file.path("a_compile_sites/nhd/", 
                         paste0(huc4, ".zip")))
      }
      
      # open the NHD flowline layer, coerce to a {sf} object
      huc4_fl <- st_read(file.path("a_compile_sites/nhd/",
                                   paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")),
                         layer = "NHDFlowline") %>% 
        # only grab stream/river and artificail path
        # 556 = coastline, 428 = pipeline, 336 = canal/ditch
        # 460 = stream/river, 468 = drainageway, 558 = artificial path (in waterbody),
        # 420 = underground conduit, 334 = connector
        filter(ftype %in% c(460, 558)) %>% 
        select(fl_nhd_id = permanent_identifier, 
               fl_gnis_id = gnis_id, 
               fl_gnis_name = gnis_name, 
               fl_fcode = fcode) %>% 
        rowid_to_column("fl_id") %>% 
        mutate(fl_nhd_source = "NHDBestRes",
               fl_stream_order = NA, # add this column in for binding, no streamorder
               # in best res
               fl_nhd_id = as.character(fl_nhd_id))
    }
    
    # per usual, make sure geo is valid
    # try to make valid polygons 
    huc4_fl <- huc4_fl %>% 
      st_make_valid()
    
    # pull out geometries that are still invalid, if any
    invalid <- huc4_fl[!st_is_valid(huc4_fl), ]
    
    # if there are any, simplify (st_simplify usually fails here, so using 
    # rmapshaper::ms_simplify())
    if (nrow(invalid) > 0) {
      sf_use_s2(TRUE) # make sure that we're using spherical geometry here
      fl_less <- huc4_fl[!huc4_fl$fl_nhd_id %in% invalid$fl_nhd_id, ]
      # for the rare cases that this doesn't work, we include a little error
      # handling here
      try(fixed <- invalid %>% 
            ms_simplify(keep = 0.75))
      if ("fixed" %in% ls()) {
        huc4_fl <- bind_rows(fl_less, fixed)
      } else {
        huc4_fl <- fl_less
      }
    }
    
    # NHD Best res is often in other crs (NAD83), so the points need to be converted if 
    # the flowlines are.
    
    if (st_crs(huc4_fl) != st_crs(sf_subset)) {
      sf_subset <- sf_subset %>% 
        st_transform(crs = st_crs(huc4_fl))
    }
    
    # walk through all of the sites and calculate how many flowlines they
    # intersect with given the buffer for GEE extraction. this assumes that the
    # buffer does not extend beyond the HUC boundary
    intersecting_flowlines <-  tibble(siteSR_id = sf_subset$siteSR_id,
                                      number_int_fl = map_vec(.x = sf_subset$siteSR_id,
                                                              .f = \(.x) {
                                                                buffered_point <- sf_subset %>% 
                                                                  filter(siteSR_id == .x) %>% 
                                                                  st_buffer(GEE_buffer)
                                                                intersected_features <- st_intersects(buffered_point, huc4_fl)
                                                                lengths(intersected_features)
                                                              }))
    
    
    
    
    # we'll associate flowlines across all sites. locs are paired to
    # waterbodies in add_NHD_waterbody_to_sites()
    huc4_flowline_points <- sf_subset %>%
      filter(grepl("river|stream|lake|reservoir", MonitoringLocationTypeName, ignore.case = T))
    
    # Assign flowline info to flowline points -------------------------------------
    
    # check to see if there are any points overlapping, if so, run matching
    # process. otherwise, return NULL
    
    if (nrow(huc4_flowline_points) > 0) {
      
      # Here, we will just grab the closest flowline and the distance to that 
      # flowline. For each of them, arrange by fl_id for proper st_distance measure.
      matched <- huc4_flowline_points %>%
        mutate(fl_id = st_nearest_feature(., huc4_fl)) %>%
        left_join(., huc4_fl %>% st_drop_geometry()) %>%
        arrange(fl_id)
      
      huc4_matched <- matched %>%
        select(siteSR_id, fl_id) %>%
        st_drop_geometry() %>%
        right_join(huc4_fl, .) %>%
        arrange(fl_id)
      
      matched <- matched %>%
        mutate(dist_to_fl = as.numeric(round(st_distance(matched, huc4_matched, by_element = TRUE)))) %>%
        # if the distance to the flowline is > 500m, recode all the flowline info 
        # ** if ** the location type is river/stream, otherwise the distance can 
        # stay for lake/res, since the distance could be large for large waterbodies
        mutate(across(all_of(c("fl_nhd_id", "fl_gnis_id", "fl_gnis_name", "fl_stream_order", "fl_fcode")),
                      ~ if_else(dist_to_fl > 500 & grepl("river|stream", MonitoringLocationTypeName, ignore.case = T),
                                NA,
                                .))) %>%
        select(-fl_id)
      
      #join the matched and matched together, flag fl assignment
      assignment <- matched %>%
        # 0 = point <= 100m proximate to flowline (nhd_id info, distance < 100)
        # 1 = point between 100m and GEE buffer distance proximate to flowline (nhd_id info and distance info)
        # 2 = point between GEE buffer distance and 500m proximate to flowline (nhd_id info and distance info)
        # 3 = point unable to be assigned to flowline for a stream site (no nhd_id, but
        #     distance info, dist > 500m)
        # 4 = point > 500m proximate to flowline, but a lake/res site ()
        # 5 = point does not have HUC8 assignment, so no flowline assigned (not assigned here)
        mutate(flag_fl = case_when(!is.na(fl_nhd_id) & dist_to_fl <= 100 ~ 0,
                                   !is.na(fl_nhd_id) & between(dist_to_fl, 100, GEE_buffer) ~ 1,
                                   !is.na(fl_nhd_id) & between(dist_to_fl, GEE_buffer, 500) ~ 2,
                                   is.na(fl_nhd_id) & !is.na(dist_to_fl) ~ 3,
                                   !is.na(fl_nhd_id) & dist_to_fl > 500 & 
                                     grepl("lake|pond|reservoir", MonitoringLocationTypeName, ignore.case = T) ~ 4))
      
      # return unique site info, huc code, and all the flowline info; also intersecting
      # flowlines for all sites in huc
      list(assignment %>% 
             st_drop_geometry() %>% 
             select(siteSR_id, MonitoringLocationIdentifier, HUCEightDigitCode,
                    all_of(starts_with("fl_")), dist_to_fl, flag_fl),
           intersecting_flowlines
      )
      
    } else {
      
      # if there are no flowline/res points in the HUC4, return NULL
      NULL
      
    }
    
  },
  
  # add error handling and note the huc4 if this fails
  error = function(e) {
    # if subset failed, note and go to next 
    message(paste0("HUC4 ", huc4, " was not able to be processed, 
                     noting in '4_compile_sites/mid/huc4_fl_no_process.txt'"))
    if (!file.exists("a_compile_sites/mid/huc4_fl_no_process.txt")) {
      write_lines(huc4, file = "a_compile_sites/mid/huc4_fl_no_process.txt")
      return(NULL)
    } else {
      text <- read_lines("a_compile_sites/mid/huc4_fl_no_process.txt")
      new_text <- c(text, huc4)
      write_lines(new_text, "a_compile_sites/mid/huc4_fl_no_process.txt")
      return(NULL)
    }
  })
  
}
