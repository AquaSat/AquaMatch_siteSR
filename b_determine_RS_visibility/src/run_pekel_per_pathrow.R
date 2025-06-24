#' @title Run Pekel script per pathrow
#' 
#' @description
#' Function to run the Pekel script for a specified WRS2 pathrow.
#' 
#' @param WRS_pathrow pathrow to run the Pekel script on
#' @returns Silently writes a text file of the current pathrow (for use in the
#' Python script). Silently triggers GEE to start stack acquisition per pathrow.
#' 
#' 
run_pekel_per_pathrow <- function(WRS_pathrow) {
  write_lines(WRS_pathrow, "5_determine_RS_visibility/run/current_pathrow.txt", sep = "")
  source_python("5_determine_RS_visibility/py/run_pekel_per_pathrow.py")
}
