# Created by use_targets()

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)

# Set general configuration setting: -----------------------------

general_config <- "admin_update"


# Set up crew controller for multicore processing ------------------------

controller_cores <- crew_controller_local(
  workers = parallel::detectCores()-1,
  seconds_idle = 12
)


# Set target options: ---------------------------------------

tar_option_set(
  # packages that {targets} need to run for this workflow
  packages = c("tidyverse", "sf"),
  memory = "transient",
  garbage_collection = TRUE,
  # set up crew controller
  controller = controller_cores
)


# Define targets workflow -------------------------------------------------

# Run the R scripts with custom functions:
tar_source(c("a_compile_sites.R",
             "b_determine_RS_visibility.R"
             # "c_siteSR_stack.R",
             # "d_qa_stack.R"
))

# and load the global functions
tar_source("src/")

# The list of targets/steps
config_targets <- list(
  
  # General config ----------------------------------------------------------
  
  # Grab configuration information for the workflow run (config.yml)
  tar_target(
    name = siteSR_config,
    # The config package does not like to be used with library()
    command = config::get(config = general_config),
    cue = tar_cue("always")
  ),
  
  # Check for Google Drive folder for siteSR output path, create it if it
  # doesn't exist
  tar_target(
    name = check_drive_parent_folder,
    command = tryCatch({
      drive_auth(siteSR_config$google_email)
      drive_ls(siteSR_config$drive_project_folder)
    }, error = function(e) {
      drive_mkdir(str_sub(siteSR_config$drive_project_folder, 1, -2))  
    }),
    packages = "googledrive",
    cue = tar_cue("always")
  ),
  
  # Check for targets subfolder, create if not present
  tar_target(
    name = check_targets_drive,
    command = {
      check_drive_parent_folder
      tryCatch({
        drive_auth(siteSR_config$google_email)
        drive_ls(paste0(siteSR_config$drive_project_folder, "targets/"))
      }, error = function(e) {
        # if the outpath doesn't exist, create it along with a "stable" subfolder
        drive_mkdir(name = "targets",
                    path = siteSR_config$drive_project_folder)
      })
      return(paste0(siteSR_config$drive_project_folder, "targets/"))
    },
    packages = "googledrive",
    cue = tar_cue("always")
  )
  
)

# Full targets list
c(config_targets,
  a_compile_sites,
  b_determine_RS_visibility
  # c_siteSR_stack,
  # d_qa_stack
)
