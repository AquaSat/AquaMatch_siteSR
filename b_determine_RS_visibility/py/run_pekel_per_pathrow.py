#import modules
import ee
import os 
import time
import pandas as pd
import numpy as np

# LOAD ALL THE CUSTOM FUNCTIONS -----------------------------------------------

def csv_to_eeFeat(df, proj, chunk, chunk_size):
    """Function to create an eeFeature from the location data

    Args:
        df: point locations .csv file with Latitude and Longitude
        proj: CRS projection of the points
        chunk: iteration through the dataframe (defined in process chunks)
        chunk_size: number of sites in chunk

    Returns:
        ee.FeatureCollection of the points 
    """
    features = []
    # Calculate start and end indices for the current chunk
    range_min = chunk_size * chunk
    range_max = min(chunk_size * (chunk + 1), len(df))
    
    for i in range(range_min, range_max):
        try:
            row = df.iloc[i]
            x, y = row['Longitude'], row['Latitude']
            latlong = [x, y]
            loc_properties = {'system:index': str(row['id']), 'id': str(row['id'])}
            g = ee.Geometry.Point(latlong, proj)
            feature = ee.Feature(g, loc_properties)
            features.append(feature)
        except KeyError as e:
            print(f"KeyError at index {i}, skipping to next iteration")
            continue  # skip to the next iteration
    
    return ee.FeatureCollection(features)


def maximum_no_of_tasks(MaxNActive, waitingPeriod):
  """ Function to limit the number of tasks sent to Earth Engine at one time to avoid time out errors
  
  Args:
      MaxNActive: maximum number of tasks that can be active in Earth Engine at one time
      waitingPeriod: time to wait between checking if tasks are completed, in seconds
      
  Returns:
      None.
  """
  ## maintain a maximum number of active tasks
  ## initialize submitting jobs
  ts = list(ee.batch.Task.list())
  NActive = 0
  for task in ts:
     if ('RUNNING' in str(task) or 'READY' in str(task)):
         NActive += 1
  ## wait if the number of current active tasks reach the maximum number
  ## defined in MaxNActive
  while (NActive >= MaxNActive):
    time.sleep(waitingPeriod) # if reach or over maximum no. of active tasks, wait for 2min and check again
    ts = list(ee.batch.Task.list())
    NActive = 0
    for task in ts:
      if ('RUNNING' in str(task) or 'READY' in str(task)):
        NActive += 1
  return()


# get locations and yml from data folder
yml = pd.read_csv('5_determine_RS_visibility/run/yml.csv')

eeproj = yml['ee_proj'][0]
#initialize GEE
ee.Initialize(project = eeproj)

# get EE/Google settings from yml file
proj = yml['proj'][0]
out_folder = "pekel_v" + yml['run_date'][0]

run_date = yml['run_date'][0]

# gee processing settings
site_buffer = yml['site_buffer'][0]

# get extent info
extent = (yml['extent'][0]
  .split('+'))
  
# get current pathrow
with open('5_determine_RS_visibility/run/current_pathrow.txt', 'r') as file:
  pathrows = file.read()

# read locations and filtere for this pathrow
locations = (pd.read_csv('5_determine_RS_visibility/run/locs_with_wrs_for_pekel.csv', 
                      dtype = ({"id": np.int32, 
                                "Latitude": np.float64, 
                                "Longitude": np.float64, 
                                "WRSPR": str})))
                                
filtered_locs = locations[locations['WRSPR'] == pathrows]


##############################################
##---- GET EE FEATURE COLLECTIONS       ----##
##############################################

# get newest version of pekel
# Jean-Francois Pekel, Andrew Cottam, Noel Gorelick, Alan S. Belward, 
# High-resolution mapping of global surface water and its long-term changes. 
# Nature 540, 418-422 (2016). (doi:10.1038/nature20584)
pekel = (ee.Image("JRC/GSW1_4/GlobalSurfaceWater")
  .select("occurrence"))

# pull using AquaSat V1 code from MR
def get_occurrence(point):
  """ Function to buffer a point and pull summary statistics for Pekel water ocurrence
  
  Args:
    point: earth engine point feature to extract Pekel summaries for
    
  Returns:
    out: earth engine point feature with max, min, median summaries for Pekel occurrence
  """
  # Define a buffer around each point, buffer must be hardcoded here, for unknown
  # reasons
  buff_point = ee.Feature(point).buffer(ee.Number.parse(str(site_buffer))).geometry() 
  # Clip the pekel mask to this buffer
  pekclip = pekel.clip(buff_point)
  # Reduce the buffer to pekel min and max
  pekMM = pekclip.reduceRegion(ee.Reducer.minMax(), buff_point, 30)
  # Add another reducer to get the median pekel occurence
  pekMed = pekclip.reduceRegion(ee.Reducer.median(), buff_point, 30)
  # Define the output features
  out = (point.set({'occurrence_max': pekMM.get('occurrence_max')})
              .set({'occurrence_min': pekMM.get('occurrence_min')})
              .set({'occurrence_med': pekMed.get('occurrence')}))
  return out


# Map the get_occurrence function over the 5000 or so created sites
def process_subset(df_subset, chunk, chunk_size, wrs_pathrow):
    """
    This function processes a subset of the DataFrame.
    Replace this with your actual processing function.
    """

    locs_feature = csv_to_eeFeat(df_subset, yml['location_crs'][0], chunk, chunk_size)

    outdata = locs_feature.map(get_occurrence)
    #Define a data export 
    dataOut = (ee.batch.Export.table.toDrive(collection = outdata,
                                            description = "Pekel_Visibility_" + wrs_pathrow + "_" + str(chunk),
                                            folder = out_folder,
                                            fileFormat = 'csv'))
    
    # check for number of tasks running
    maximum_no_of_tasks(20, 60)
    
    # send next task if there isn't too much in the queue!
    dataOut.start()
    
    return ()


def process_dataframe_in_chunks(df, wrs_pathrow, chunk_size = 5000):
    """
    Process a DataFrame in chunks of specified size.
    
    Args:
    df (pandas.DataFrame): The input DataFrame
    chunk_size (int): The number of rows in each chunk (default: 5000)
    
    Returns:
    none
    
    """
    print(f"Sending sites from WRS path-row {wrs_pathrow} to GEE.")
    
    # Calculate the number of chunks
    num_chunks = len(df) // chunk_size + (1 if len(df) % chunk_size != 0 else 0)
    
    for i in range(num_chunks):
        # Calculate start and end indices for the current chunk
        start_idx = i * chunk_size
        end_idx = min((i + 1) * chunk_size, len(df))
        
        # Subset the DataFrame
        df_subset = df.iloc[start_idx:end_idx]
        
        # Process the subset and store the result
        result = process_subset(df_subset, i, chunk_size, wrs_pathrow)

        print(f"Sent chunk {i+1}/{num_chunks}")
    
    return ()



# and then actualy process the chunks!
process_dataframe_in_chunks(df = filtered_locs, wrs_pathrow = pathrows)
