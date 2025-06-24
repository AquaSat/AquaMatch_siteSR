#' @title Run GEE script per Landsat path-row for siteSR
#' 
#' @description
#' Function to run the Landsat pull for a specified WRS2 path-row
#' 
#' @param WRS_pathrow Landsat path-row to run the GEE pull on
#' @returns Silently writes a text file of the current path-row (for use in the
#' Python script). Silently triggers GEE to start stack acquisition for that 
#' path-row.
#' 
#' 
run_siteSR_per_pathrow <- function(WRS_pathrow) {
  # document WRS tile for python script
  write_lines(WRS_pathrow, "6_siteSR_stack/out/current_pathrow.txt", sep = "")
  # run the python script
  source_python("6_siteSR_stack/py/run_siteSR_per_pathrow.py")
}