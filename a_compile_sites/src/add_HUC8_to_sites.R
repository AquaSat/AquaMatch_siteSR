#' @title Add HUC8 information to sites if not populated
#' 
#' @description
#' This function uses the location of a site to determine the HUC8 it
#' falls within and assigns that text to the `HUCEightDigitCode` column native
#' to the WQP/NIWS site information. This is only run for sites where the 
#' `HUCEightDigitCode` is NA
#' 
#' @param sites_without_HUC a simple feature object of WQP/NWIS sites that do not have
#' the `HUCEightDigitCode` column populated.
#' 
#' @returns a simple feature object with `HUCEightDigitCode` populated if the 
#' sites are associated with a HUC8. Silently saves a file of sites that could
#' not be resolved to `a_compile_sites/out/sites_unable_to_assign_HUC08.csv`
#' 
#' 
add_HUC8_to_sites <- function(sites_without_HUC) {
  # for each site, get the HUC8 associated with it and assign that value to the
  # upstream dataset 
  HUC08_assigned <- sites_without_HUC %>% 
    split(f = .$siteSR_id) %>% 
    map(.x = .,
        .f = ~ {
          tryCatch({
            # we can use the nhdplusTools package to grab this
            one_huc <- get_huc(.x, type = "huc08", buffer = 0.1)
            .x$HUCEightDigitCode <- one_huc$huc8
            return(.x)
          },
          error = function(e) {
            # if this errors because no HUC8 is available, return the point, 
            # without HUC assigned.
            return(.x)
          }
          )}) %>%  
    bind_rows() %>% 
    filter(!is.na(HUCEightDigitCode))
  # make a list of the sites that couldn't be assigned
  failed_to_assign <- sites_without_HUC %>% 
    filter(!siteSR_id %in% HUC08_assigned$siteSR_id)
  # save to file
  write_csv(failed_to_assign, paste0("a_compile_sites/out/", 
                                     unique(sites_without_HUC$source), 
                                     "_sites_unable_to_assign_HUC08.csv"))
  # return assigned file
  bind_rows(HUC08_assigned, failed_to_assign)
}
