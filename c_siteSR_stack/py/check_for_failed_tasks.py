import ee
from pandas import read_csv
import time
import os

# get configs from yml file
yml = read_csv("b_determine_RS_visibility/run/yml.csv")
# assign proj
eeproj = yml["ee_proj"][0]
# initialize GEE with proj
ee.Initialize(project = eeproj)
# grab run date
run_date = yml["run_date"][0]
# make task error file name
fn = "GEE_task_errors_v" + run_date + ".csv"

# get a list of all the submitted tasks (these data time out at 10 days, so any 
# failed tasks may not be indicative of ALL failed tasks if the runtime of the
# pull is greater than 10 days)
ts = list(ee.batch.Task.list())

# for each of the tasks, see if any failed, if so, add a line to a csv file with the task id
for task in ts:
   if ("FAIL" in task.status()['state'] and run_date in task.status()['description']):
       # add the task description to a file called 'GEE_task_errors.csv'
       with open(os.path.join('c_siteSR_stack/out/', fn), 'a') as f:
          f.write(task.status()['description'] + '\n')
