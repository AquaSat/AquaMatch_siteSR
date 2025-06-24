# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "6_siteSR_stack/src/")

# Set up python virtual environment ---------------------------------------
library(reticulate)
tar_source("python/pySetup.R")


# Define {targets} workflow -----------------------------------------------

if (config::get(config = general_config)$run_GEE) {
  
  # target objects in workflow
  p6_siteSR_stack <- list(
    
    # general configuration ---------------------------------------------------
    
    # make directories if needed
    tar_target(
      name = p6_check_dir_structure,
      command = {
        directories = c("6_siteSR_stack/mid/",
                        "6_siteSR_stack/down/",
                        "6_siteSR_stack/run/",
                        "6_siteSR_stack/out/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always")
    ),
    
    # save the output of RS-visible sites to this directory
    tar_target(
      name = p6_store_visible_sites_for_GEE,
      command = write_csv(p5_visible_sites, "6_siteSR_stack/run/visible_locs_with_WRS.csv")
    ),
    
    # Check for GEE export subfolder, create if not present
    tar_target(
      name = p6_check_siteSR_folder,
      command = {
        p0_check_drive_parent_folder
        tryCatch({
          drive_auth(p5_yml$google_email)
          drive_ls(paste0("siteSR_v", p5_yml$run_date))
        }, error = function(e) {
          # if the outpath doesn't exist, create it
          drive_mkdir(name = paste0("siteSR_v", p5_yml$run_date),
                      path = p5_yml$proj_parent_folder)
        })
      },
      packages = "googledrive",
      cue = tar_cue("always")
    ),
    
    
    # make siteSR pull ----------------------------------------------
    
    # get WRS pathrow
    tar_target(
      name = p6_WRS_pathrows,
      command = get_WRS_pathrows(detection_method = "site", 
                                 yaml = p5_yml, 
                                 locs = p5_visible_sites,
                                 out_folder = "6_siteSR_stack/out/"),
      packages = c("readr", "sf"),
    ),
    
    # check to see that all sites and buffers are completely contained by each pathrow
    # and assign wrs path-rows for all sites based on configuration buffer.
    tar_target(
      name = p6_siteSR_locs_filtered,
      command = check_if_fully_within_pr(WRS_pathrow = p6_WRS_pathrows, 
                                         locations = p5_visible_sites, 
                                         yml = p5_yml),
      pattern = map(p6_WRS_pathrows),
      packages = c("tidyverse", "sf", "arrow")
    ),
    
    tar_file(
      name = p6_siteSR_script,
      command = "6_siteSR_stack/py/run_siteSR_per_pathrow.py"
    ), 
    
    # Run EE siteSR pull pull 
    tar_target(
      name = p6_run_siteSR,
      command = {
        p5_yml
        p6_siteSR_script
        p6_siteSR_locs_filtered
        run_siteSR_per_pathrow(WRS_pathrow = p6_WRS_pathrows)
      },
      pattern = p6_WRS_pathrows,
      packages = "reticulate",
      deployment = "main"
    ),
    
    # wait for all earth engine tasks to be completed
    tar_target(
      name = p6_siteSR_tasks_complete,
      command = {
        p6_run_siteSR
        source_python("6_siteSR_stack/py/siteSR_wait_for_completion.py")
      },
      packages = "reticulate",
      deployment = "main"
    ),
    
    # since we can't easily track if tasks have failed, and we send a lot of tasks
    # in this process, let's check for any failed tasks and add them to 
    # b_pull_Landsat_SRST_poi/out/GEE_failed_tasks_vRUN_DATE.txt
    
    tar_file(
      name = p6_failed_tasks_script,
      command = "6_siteSR_stack/py/check_for_failed_tasks.py"
    ), 
    
    tar_target(
      name = p6_check_for_failed_tasks,
      command = {
        p6_siteSR_tasks_complete
        source_python(p6_failed_tasks_script)
      },
      packages = "reticulate",
      deployment = "main",
      error = "continue" # sometimes this will error out if you've completed a lot 
      # tasks in your ee-project
    ),
    
    
    # download/collated siteSR stacks -----------------------------------------
    
    # download siteSR files
    tar_target(
      name = p6_siteSR_contents,
      command = {
        # make sure that siteSR tasks complete
        p6_siteSR_tasks_complete
        # authorize Google
        drive_auth(email = p5_yml$google_email)
        # create the folder path as proj_folder and run_date
        drive_folder <- paste0(p5_yml$proj_parent_folder, "siteSR_v", p5_yml$run_date)
        # get a list of files in the project file
        drive_ls(path = drive_folder) %>% 
          select(name, id)
      },
      packages = c("tidyverse", "googledrive")
    ), 
    
    # target with list of data segments:
    tar_target(
      name = p6_data_segments,
      command = c("metadata", "LS457", "LS89"),
      deployment = "main"
    ),
    
    # set mission groups
    tar_target(
      name = p6_mission_groups,
      command = c("LS457", "LS89"),
      deployment = "main"
    ),
    
    # set dswe types
    tar_target(
      name = p6_dswe_types,
      command = {
        dswe = NULL
        if (grepl("1", p5_yml$DSWE_setting)) {
          dswe = c(dswe, "DSWE1")
        } 
        if (grepl("1a", p5_yml$DSWE_setting)) {
          dswe = c(dswe, "DSWE1a")
        } 
        if (grepl("3", p5_yml$DSWE_setting)) {
          dswe = c(dswe, "DSWE3")
        } 
        dswe
      },
      deployment = "main"
    ), 
    
    # download all files, branched by data segments
    tar_target(
      name = p6_download_files,
      command = download_csvs_from_drive(local_folder = "6_siteSR_stack/down/",
                                         file_type = p6_data_segments,
                                         drive_contents = p6_siteSR_contents,
                                         yml = p5_yml,
                                         depends = p6_check_dir_structure),
      packages = c("tidyverse", "googledrive"),
      pattern = map(p6_data_segments)
    ),
    
    # collate all files - these end up being pretty big without filtering, so we 
    # need to break them up as metadata, then site pulls. The site pulls also need
    # to be split by dswe type and mission, otherwise the files are too big for R
    # to handle
    
    # make metadata file - this doesn't require filtering of dswe or mission
    tar_target(
      name = p6_make_collated_metadata,
      command = collate_csvs_from_drive(file_type = "metadata",
                                        yml = p5_yml,
                                        dswe = NULL,
                                        separate_missions = FALSE,
                                        depends = p6_download_files),
      packages = c("data.table", "tidyverse", "arrow")
    ),
    
    tar_target(
      name = p6_make_collated_point_files,
      command = collate_csvs_from_drive(file_type = p6_mission_groups,
                                        yml = p5_yml,
                                        dswe = p6_dswe_types,
                                        separate_missions = TRUE,
                                        depends = p6_download_files),
      packages = c("data.table", "tidyverse", "arrow"),
      pattern = cross(p6_mission_groups, p6_dswe_types)
    ),
    
    # Save collated files to Drive, create csv with ids -----------------------
    
    # get list of files to save to drive
    tar_target(
      name = p6_collated_siteSR_files,
      command = {
        p6_make_collated_metadata
        p6_make_collated_point_files
        list.files(file.path("6_siteSR_stack/mid/",
                             p5_yml$run_date),
                   full.names = TRUE)
      }
    )
    ,
    
    tar_target(
      name = p6_check_Drive_collated_folder,
      command =  {
        p0_check_drive_parent_folder
        tryCatch({
          drive_auth(p5_yml$google_email)
          if (p5_yml$proj_parent_folder != "") {
            parent_folder <- p5_yml$proj_parent_folder
            version_path <- paste0(p5_yml$proj_parent_folder,
                                   paste0("collated_raw_v", p5_yml$run_date, "/"))
            
          } else {
            parent_folder <- p5_yml$proj_folder
            version_path <- paste0(p5_yml$proj_folder,
                                   paste0("collated_raw_v", p5_yml$run_date, "/"))
          }
          # check for doubles!
          drive_ls(version_path)
        }, error = function(e) {
          # if there is an error, check both the 'collated_raw' folder and the 'version'
          # folder
          drive_mkdir(path = parent_folder, name = paste0("collated_raw_v", p5_yml$run_date))
        })
        return(version_path)
      },
      packages = "googledrive",
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = p6_send_collated_files_to_drive,
      command = export_single_file(file_path = p6_collated_siteSR_files,
                                   drive_path = p6_check_Drive_collated_folder,
                                   google_email = p5_yml$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = p6_collated_siteSR_files
    ),
    
    tar_target(
      name = p6_save_collated_Drive_info,
      command = {
        drive_ids <- p6_send_collated_files_to_drive %>%
          select(name, id)
        write_csv(drive_ids,
                  "6_siteSR_stack/out/raw_collated_files_drive_ids.csv")
        drive_ids
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
} else {
  
  p6_siteSR_stack <- list(
    
    # make directories if needed
    tar_target(
      name = p6_check_dir_structure,
      command = {
        directories = c("6_siteSR_stack/mid/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always")
    ),
    
    tar_file_read(
      name = p6_save_collated_Drive_info,
      command = "6_siteSR_stack/out/raw_collated_files_drive_ids.csv",
      read = read_csv(!!.x)
    ),
    
    tar_target(
      name = p6_collated_siteSR_files,
      command = {
        p6_check_dir_structure
        retrieve_data(id_df = p6_save_collated_Drive_info, 
                      local_folder = paste0("6_siteSR_stack/mid/",
                                            p0_siteSR_config$pekel_gee_version), 
                      google_email = p0_siteSR_config$google_email)
        list.files(path = paste0("6_siteSR_stack/mid/",
                                 p0_siteSR_config$pekel_gee_version), 
                   full.names = TRUE)
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
}



