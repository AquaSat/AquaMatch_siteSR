# Targets list to compile sites and attribute each feature to a waterbody or
# flowline

# Define `a` group --------------------------------------------------------

# Source the functions that will be used to build the targets in `a_compile_sites`
tar_source(files = "a_compile_sites/src/")

if (config::get(config = general_config)$compile_locations) {
  
  a_compile_sites <- list(
    
    # make directories if needed
    tar_target(
      name = a_check_dir_structure,
      command = {
        directories <- c("a_compile_sites/mid/",
                         "a_compile_sites/out/",
                         "a_compile_sites/out/failed_HUC/",
                         "a_compile_sites/nhd/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always"),
    ),
    
    # Get unique sites from WQP and NWIS -------------------------------------
    
    # Make list of FIPS state descriptions
    tar_target(
      name = a_fips_descriptions,
      command = {
        # grab the xml from the National Water Quality Monitoring Council
        read_xml("https://www.waterqualitydata.us/Codes/statecode?countrycode=US") %>% 
          xml_find_all(., ".//Code") %>% 
          xml_attr(., "desc")
      },
      packages = c("tidyverse", "xml2")
    ),
    
    # map the descriptions to get all filtered site metadata for WQP
    tar_target(
      name = a_WQP_site_metadata,
      command = get_site_info(fips_state_code_desc = a_fips_descriptions,
                              site_source = "WQP"),
      pattern = map(a_fips_descriptions),
      packages = c("tidyverse", "dataRetrieval")
    ),
    
    # map the descriptions to get all filtered site metadata for WQP
    tar_target(
      name = a_NWIS_site_metadata,
      command = get_site_info(fips_state_code_desc = a_fips_descriptions,
                              site_source = "NWIS"),
      pattern = map(a_fips_descriptions),
      packages = c("tidyverse", "dataRetrieval")
    ),
    
    # Project and transform sites as needed - this is done separately since the
    # metadata is not the same across the two data sources (WQP/NWIS)
    tar_target(
      name = a_harmonized_WQP_sites,
      command = {
        # use function to harmonize across all CRS
        harmonized_crs <- harmonize_crs(sites = a_WQP_site_metadata)
        # return sf, with only applicable columns
        harmonized_crs  %>% 
          select(org_id = OrganizationIdentifier, loc_id = MonitoringLocationIdentifier,
                 MonitoringLocationTypeName, HUCEightDigitCode, WGS84_Latitude, WGS84_Longitude,
                 source) %>% 
          st_drop_geometry() %>% 
          unique() %>% 
          rowid_to_column("siteSR_id") %>% 
          mutate(siteSR_id = paste0("WQP_", siteSR_id))
      },
      packages = c("tidyverse", "sf"),
    ),
    
    # NWIS data lat/lon that start with `dec_` are all stored in NAD83
    tar_target(
      name = a_harmonized_NWIS_sites,
      command = {
        # create sf and transform to WGS84
        to_wgs84 <- a_NWIS_site_metadata %>% 
          st_as_sf(coords = c("dec_long_va", "dec_lat_va"),
                   crs = "EPSG:4269",
                   remove = FALSE) %>%
          st_transform(crs = "EPSG:4326")
        
        # store harmonized Latitude and Longitude in site list
        new_coords <- to_wgs84 %>% st_coordinates()
        
        # add WGS84 lat/long
        to_wgs84$WGS84_Longitude = round(new_coords[,1], 5)
        to_wgs84$WGS84_Latitude = round(new_coords[,2], 5)
        
        # return sf, with only applicable columns
        to_wgs84  %>% 
          select(org_id = agency_cd, loc_id = site_no, 
                 site_tp_cd, WGS84_Latitude, WGS84_Longitude, source) %>% 
          st_drop_geometry() %>% 
          unique() %>%
          rowid_to_column("siteSR_id") %>% 
          mutate(siteSR_id = paste0("NWIS_", siteSR_id))
      },
      packages = c("tidyverse", "sf"),
    ),
    
    # Collate site lists from AquaMatch Harmonize pipeline --------------------
    
    ## read the ids csv
    tar_file_read(
      name = a_AquaMatch_chla_drive_ids,
      command = "a_compile_sites/in/chl_drive_ids.csv",
      read = read_csv(!!.x)
    ),
    tar_file_read(
      name = a_AquaMatch_doc_drive_ids,
      command = "a_compile_sites/in/doc_drive_ids.csv",
      read = read_csv(!!.x)
    ),
    tar_file_read(
      name = a_AquaMatch_sdd_drive_ids,
      command = "a_compile_sites/in/sdd_drive_ids.csv",
      read = read_csv(!!.x)
    ),
    tar_file_read(
      name = a_AquaMatch_tss_drive_ids,
      command = "a_compile_sites/in/tss_drive_ids.csv",
      read = read_csv(!!.x)
    ),
    
    # retrieve site targets
    tar_target(
      name = a_AquaMatch_chla_sites,
      command = {
        a_check_dir_structure
        retrieve_target(target = "p3_chla_harmonized_site_info", 
                        id_df = a_AquaMatch_chla_drive_ids,
                        local_folder = "a_compile_sites/mid/", 
                        google_email = siteSR_config$google_email, 
                        file_type = "rds",
                        date_stamp = "20240701") %>% 
          filter(!MonitoringLocationIdentifier %in% a_WQP_site_metadata$MonitoringLocationIdentifier)
      }, 
      packages = c("tidyverse", "googledrive")
    ),
    tar_target(
      name = a_AquaMatch_doc_sites,
      command = {
        a_check_dir_structure
        retrieve_target(target = "p3_doc_harmonized_site_info", 
                        id_df = a_AquaMatch_doc_drive_ids,
                        local_folder = "a_compile_sites/mid/", 
                        google_email = siteSR_config$google_email, 
                        file_type = "rds",
                        date_stamp = "20240701") %>% 
          filter(!MonitoringLocationIdentifier %in% a_WQP_site_metadata$MonitoringLocationIdentifier)
      },
      packages = c("tidyverse", "googledrive")
    ),
    tar_target(
      name = a_AquaMatch_sdd_sites,
      command = {
        a_check_dir_structure
        retrieve_target(target = "p3_sdd_harmonized_site_info", 
                        id_df = a_AquaMatch_sdd_drive_ids,
                        local_folder = "a_compile_sites/mid/", 
                        google_email = siteSR_config$google_email, 
                        file_type = "rds",
                        date_stamp = "20240701") %>% 
          filter(!MonitoringLocationIdentifier %in% a_WQP_site_metadata$MonitoringLocationIdentifier)
      }, 
      packages = c("tidyverse", "googledrive")
    ),
    ## TSS 
    tar_target(
      name = a_AquaMatch_tss_sites,
      command = {
        a_check_dir_structure
        retrieve_target(target = "p3_tss_harmonized_site_info", 
                        id_df = a_AquaMatch_tss_drive_ids,
                        local_folder = "a_compile_sites/mid/", 
                        google_email = siteSR_config$google_email, 
                        file_type = "rds",
                        date_stamp = "20250430") %>% 
          filter(!MonitoringLocationIdentifier %in% a_WQP_site_metadata$MonitoringLocationIdentifier)
      }, 
      packages = c("tidyverse", "googledrive")
    ),
    
    # collate and get unique sites for AquaMatch
    tar_target(
      name = a_AquaMatch_sites,
      command = {
        site_list <- reduce(list(a_AquaMatch_chla_sites,
                                 a_AquaMatch_doc_sites,
                                 a_AquaMatch_sdd_sites,
                                 a_AquaMatch_tss_sites),
                            bind_rows) 
        # harmonize crs, select only the columns we care about and 
        harmonize_crs(site_list) %>% 
          select(org_id = OrganizationIdentifier, loc_id = MonitoringLocationIdentifier,
                 MonitoringLocationTypeName, HUCEightDigitCode, 
                 WGS84_Latitude, WGS84_Longitude) %>% 
          unique() %>% 
          rowid_to_column("siteSR_id") %>% 
          mutate(siteSR_id = paste0("AM_", siteSR_id),
                 source = "WQP")
      }
    ),
    
    # Collate all locations together --------------------------------------
    
    tar_target(
      name = a_all_site_locations,
      command = {
        # join together
        sites <- reduce(list(a_harmonized_NWIS_sites, a_harmonized_WQP_sites, a_AquaMatch_sites %>% st_drop_geometry()),
                        full_join) %>%  
          setDT(.)
        sites[, harmonized_site_type := case_when(site_tp_cd == "ST" ~ "Stream",
                                                  site_tp_cd %in% c("ST-CA", "ST-DCH") ~ "Ditch/Canal",
                                                  site_tp_cd == "LK" ~ "Lake/Reservoir",
                                                  site_tp_cd == "ES" ~ "Estuary",
                                                  grepl("stream", MonitoringLocationTypeName, ignore.case = T) ~ "Stream",
                                                  grepl("lake|reservoir", MonitoringLocationTypeName, ignore.case = T) ~ "Lake/Reservoir",
                                                  MonitoringLocationTypeName == "Estuary" ~ "Estuary",
                                                  grepl("canal|ditch", MonitoringLocationTypeName, ignore.case = T) ~ "Ditch/Canal",
                                                  .default = "Other")]
        sites %>% 
          relocate(siteSR_id, org_id, loc_id, harmonized_site_type, WGS84_Latitude, WGS84_Longitude, source, HUCEightDigitCode) %>% 
          filter(WGS84_Latitude != 0 & WGS84_Longitude != 0 & abs(WGS84_Latitude) != 1 & abs(WGS84_Longitude) != 1) %>% 
          st_as_sf(coords = c("WGS84_Longitude", "WGS84_Latitude"),
                   crs = "EPSG:4326", 
                   remove = FALSE) 
      },
      packages = c("data.table", "tidyverse", "sf", "targets")
    ), 
    
    # save this as a .rds file in drive
    tar_target(
      name = a_save_all_site_locs_drive,
      command = {
        export_single_target(target = a_all_site_locations,
                             drive_path = check_targets_drive,
                             stable = FALSE,
                             google_email = siteSR_config$google_email,
                             date_stamp = siteSR_config$collated_site_version,
                             file_type = "rds")
      },
      packages = c("tidyverse", "googledrive"),
    ),
    
    # save this as a .csv file locally for GEE run
    tar_target(
      name = a_save_all_site_locs_local,
      command = a_all_site_locations %>% 
        st_drop_geometry() %>% 
        write_csv(., "a_compile_sites/out/a_all_site_locations.csv")
    ),
    
    # get the drive id info
    tar_target(
      name = a_all_site_locs_Drive_id,
      command = {
        get_file_ids(google_email = siteSR_config$google_email,
                     drive_folder = check_targets_drive, 
                     file_path = "a_compile_sites/out/all_site_locations_drive_id.csv", 
                     depend = list(a_save_all_site_locs_local, a_save_all_site_locs_drive),
                     filter_by = "a_all_site_locations")
      },
      packages = c("tidyverse", "googledrive")
    ),
    
    # Associate location with NHD waterbody and flowline ------------------------
    
    # we're going to group the sites by their data source and org id, mostly for 
    # the HUC assignment step to reduce long processing times per branch
    tar_target(
      name = a_grouped_sites,
      command = a_all_site_locations %>% 
        group_by(source, harmonized_site_type) %>% 
        tar_group(),
      iteration = "group",
      packages = c("tidyverse", "sf", "targets")
    ),
    
    # Nearly all WQP sites have a HUC8 reported in the `HUCEightDigitCode` field, 
    # but a few need it assigned (or are assigned incorrectly), as do all of the NWIS sites
    # this step also adds a flag to gap-filled HUC8 fields:
    # 0 = HUC8 reported in WQP site information, matches nhdplusTools assignment
    # 1 = HUC8 determined from nhdplusTools (from NHD), WQP/AM site info was blank
    # 2 = HUC8 mismatch between WQP/AM assignment and nhdplusTools assignment, 
    # using nhdplusTools assignment
    # 3 = HUC8 was assigned to estuary site, but not able to be assigned using this method
    # 4 = HUC8 unable to be determined for site location
    
    # first step is to download the staged wbd dataset, since pinging the NHD API
    # is not sustainable, and repeating this 1 million times takes quite a bit of
    # time.
    tar_target(
      name = a_wbd_gdb,
      command = {
        if (!dir.exists("a_compile_sites/nhd/WBD_National_GDB/")) {
          download_wbd(outdir = "a_compile_sites/nhd/")
          unzip("a_compile_sites/nhd/WBD_National_GDB.zip", 
                exdir = "a_compile_sites/nhd/WBD_National_GDB/")
          unlink("a_compile_sites/nhd/WBD_National_GDB.zip")
        }
        read_sf("a_compile_sites/nhd/WBD_National_GDB/WBD_National_GDB.gdb", 
                layer = "WBDHU8") %>% 
          st_make_valid()
      },
      packages = c("nhdplusTools", "sf")
    ),
    
    tar_target(
      name = a_sites_add_HUC8,
      command = {
        assigned <- add_HUC8_to_sites(sites = a_grouped_sites, hucs = a_wbd_gdb)
        # create flag for huc assignment based on HUCEightDigitCode and assigned_HUC
        assigned %>% 
          mutate(flag_HUC8 = case_when(HUCEightDigitCode == assigned_HUC ~ 0,
                                       is.na(HUCEightDigitCode) & !is.na(assigned_HUC) ~ 1,
                                       HUCEightDigitCode != assigned_HUC ~ 2, 
                                       is.na(assigned_HUC) & !is.na(HUCEightDigitCode) & MonitoringLocationTypeName == "Estuary" ~ 3,
                                       is.na(HUCEightDigitCode) & is.na(assigned_HUC) ~ 4,
                                       .default = NA_real_))
      },
      pattern = map(a_grouped_sites),
      iteration = "list",
      packages = c("tidyverse", "sf", "targets", "nhdplusTools"),
    ),
    
    # Create the unique HUCs to map over, but drop those where a HUC4 was not
    # able to be assigned - processing via HUC4s is twice as fast as HUC8s.
    # Do this using DT for quick processing
    tar_target(
      name = a_HUC4_list,
      command = {
        dt <- map(a_sites_add_HUC8, setDT) %>% 
          rbindlist() 
        unique(str_sub(dt[!is.na(assigned_HUC), assigned_HUC], 1, 4))
      },
      packages = c("data.table", "tidyverse")
    ),
    
    # Get the waterbodies associated with each lake/reservoir site by HUC4, 
    # leave these in a list for other branching functions - my hope is that only
    # changed branches will be re-run and not all of the data every time.
    tar_target(
      name = a_add_NHD_waterbody_info,
      command = {
        a_check_dir_structure
        add_NHD_waterbody_to_sites(sites_with_huc = a_sites_add_HUC8,
                                   huc4 = a_HUC4_list,
                                   GEE_buffer = as.numeric(b_yml$site_buffer),
                                   huc8_wbd = a_wbd_gdb)
      },
      pattern = cross(a_HUC4_list, a_sites_add_HUC8),
      iteration = "list",
      packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
    ),
    
    # Calculate the closest flowline to each river/stream/res/lake/pond site by HUC4
    tar_target(
      name = a_add_NHD_flowline_info,
      command = {
        a_check_dir_structure
        add_NHD_flowline_to_sites(sites_with_huc = a_sites_add_HUC8,
                                  huc4 = a_HUC4_list,
                                  GEE_buffer = as.numeric(b_yml$site_buffer),
                                  huc8_wbd = a_wbd_gdb)
      },
      pattern = cross(a_HUC4_list, a_sites_add_HUC8),
      iteration = "list",
      packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
    ),
    
    # And add that waterbody and flowline info to the unique sites with HUC info
    tar_target(
      name = a_sites_with_NHD_info,
      command = {
        a_check_dir_structure
        # join the waterbody metadata data together
        waterbody_info <- map(a_add_NHD_waterbody_info,
                              function(w) {
                                w[1]}
        ) %>%
          bind_rows() 
        # and the flowine data
        flowline_info <- map(a_add_NHD_flowline_info,
                             function(f) {
                               # get the first object of the list item (nhd info with waterbody info)
                               f[1]
                             }) %>%
          bind_rows()
        georef_sites <- a_sites_add_HUC8 %>% 
          bind_rows() %>% 
          st_drop_geometry() %>% 
          # remove the targets grouping column
          select(-tar_group)
        collated_sites <- full_join(waterbody_info,
                                    flowline_info) %>%
          # add in spatial info from above
          full_join(georef_sites, .)
        # get the intersections data to add to this
        waterbody_intersections <- map(a_add_NHD_waterbody_info,
                                       function(w) {
                                         # get the second object of the list item (intersection info)
                                         w[2]
                                       }) %>%
          bind_rows()
        flowline_intersections <- map(a_add_NHD_flowline_info,
                                      function(f) {
                                        # get the second object of the list item (intersection info)
                                        f[2]
                                      }) %>%
          bind_rows()
        
        # turns out there are a few overlapping NHD waterbody polygons that create
        # a handful of extra rows here. For the purposes of this workflow, we'll
        # just grab the larger of the two overlapping polygons.
        collated_sites <- collated_sites %>%
          left_join(., waterbody_intersections) %>%
          left_join(., flowline_intersections) %>%
          arrange(-wb_areasqkm) %>%
          slice(1, .by = siteSR_id)
        # fill in flags where HUC8 was not able to be assigned
        collated_sites <- collated_sites %>%
          mutate(flag_wb = if_else(is.na(flag_wb), 3, flag_wb),
                 flag_fl = if_else(is.na(flag_fl), 4, flag_fl),
                 # flag 0 = unlikely shoreline contamination
                 # flag 1 = possible shoreline contamination
                 flag_optical_shoreline = case_when(flag_wb != 0 ~ NA,
                                                    dist_to_shore <= (as.numeric(b_yml$site_buffer) + 30) &
                                                      flag_wb == 0 ~ 1,
                                                    dist_to_shore > (as.numeric(b_yml$site_buffer) + 30) &
                                                      flag_wb == 0 ~ 0),
                 flag_thermal_MSS_shoreline = case_when(flag_wb != 0 ~ NA,
                                                        dist_to_shore <= (as.numeric(b_yml$site_buffer) + 120) &
                                                          flag_wb == 0 ~ 1,
                                                        dist_to_shore > (as.numeric(b_yml$site_buffer) + 120) &
                                                          flag_wb == 0 ~ 0),
                 flag_thermal_ETM_shoreline = case_when(flag_wb != 0 ~ NA,
                                                        dist_to_shore <= (as.numeric(b_yml$site_buffer) + 60) &
                                                          flag_wb == 0 ~ 1,
                                                        dist_to_shore > (as.numeric(b_yml$site_buffer) + 60) &
                                                          flag_wb == 0 ~ 0),
                 flag_thermal_TIRS_shoreline = case_when(flag_wb != 0 ~ NA,
                                                         dist_to_shore <= (as.numeric(b_yml$site_buffer) + 100) &
                                                           flag_wb == 0 ~ 1,
                                                         dist_to_shore > (as.numeric(b_yml$site_buffer) + 100) &
                                                           flag_wb == 0 ~ 0))
        # coerce NA -> "" when wb/fl assignment but no gnis/name
        collated_sites <- collated_sites %>% 
          mutate(across(.cols = c(wb_gnis_id, wb_gnis_name), 
                        .fns = ~ if_else(!is.na(wb_nhd_id) & is.na(.x), "", .x)),
                 across(.cols = c(fl_gnis_id, fl_gnis_name),
                        .fns = ~ if_else(!is.na(fl_nhd_id) & is.na(.x), "", .x)))
        write_csv(collated_sites,
                  paste0("a_compile_sites/out/siteSR_collated_WQP_NWIS_sites_with_NHD_info_", siteSR_config$collated_site_version, ".csv"))
        collated_sites
      },
    ),
    
    # save this target as an .RDS in Drive
    tar_target(
      name = a_export_sites_with_NHD,
      command = {
        check_targets_drive
        export_single_target(target = a_sites_with_NHD_info,
                             drive_path = check_targets_drive,
                             stable = FALSE,
                             google_email = siteSR_config$google_email,
                             date_stamp = siteSR_config$collated_site_version,
                             file_type = "rds")
      },
      packages = c("tidyverse", "googledrive"),
    ),
    
    tar_target(
      name = a_sites_with_NHD_Drive_id,
      command = {
        a_export_sites_with_NHD
        get_file_ids(google_email = siteSR_config$google_email,
                     drive_folder = check_targets_drive,
                     file_path = "a_compile_sites/out/sites_with_NHD_drive_id.csv",
                     depend = a_export_sites,
                     filter_by = "a_sites_with_NHD_info")
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
} else {
  
  a_compile_sites <- list(
    
    # load in distinct sites did file and retrieve target
    # locs w/o NHD attribution
    tar_file_read(
      name = a_all_site_locs_Drive_id,
      command = "a_compile_sites/out/all_site_locations_drive_id.csv",
      read = read_csv(!!.x),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = a_all_site_locations,
      command = retrieve_target(target = "a_all_site_locations",
                                id_df = a_all_site_locs_Drive_id, 
                                local_folder = "a_compile_sites/out/", 
                                google_email = siteSR_config$google_email,
                                date_stamp = paste0("v", siteSR_config$collated_site_version),
                                file_type = "rds"),
      packages = c("tidyverse", "googledrive")
    ),
    
    # load in the sites **with** NHD info.
    tar_file_read(
      name = a_sites_with_NHD_Drive_id,
      command = "a_compile_sites/out/sites_with_NHD_drive_id.csv",
      read = read_csv(!!.x),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = a_sites_with_NHD_info,
      command = retrieve_target(target = "a_sites_with_NHD_info",
                                id_df = a_sites_with_NHD_Drive_id, 
                                local_folder = "a_compile_sites/out/", 
                                google_email = siteSR_config$google_email,
                                date_stamp = paste0("v", siteSR_config$collated_site_version),
                                file_type = "rds"),
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
}

