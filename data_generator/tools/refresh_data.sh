#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Utility script to add mock data and refresh derived tables

set -eo pipefail

if [[ -z "$WEBHOOK" || -z "$SECRET" ]]; then
echo "Unable to proceed. Please ensure the following environment variables \
are set: WEBHOOK, SECRET"
exit 1
fi

read -p "Which version control system are you using? 
(1) GitLab
(2) GitHub

Enter a selection (1 - 2): " git_system

if [[ ${git_system} != "1" && ${git_system} != "2" ]]; then
    echo "Invalid choice for version control system"
    exit 1
fi

purge_data="n"
read -p "Do you want to delete existing data from the project? (y/n): " purge_data

if [[ ${purge_data} == "y" ]]; then

    yesno="n"
    read -p "Are you sure? This will delete ALL data that has been collected in project ${FOURKEYS_PROJECT} (y/n): " yesno
    if [[ ${yesno} != "y" ]]; then
        echo "Aborting."
        exit 0
    fi

    # drop and recreate the events_raw table
    # (why not delete the data? Because delete may fail due to https://stackoverflow.com/questions/43085896)
    bq query --use_legacy_sql=false "DROP TABLE IF EXISTS ${FOURKEYS_PROJECT}.four_keys.events_raw"
    bq mk --table -f ${FOURKEYS_PROJECT}:four_keys.events_raw ../../setup/events_raw_schema.json
fi

# insert new data
if [[ ${git_system} == "1" ]]; then
    python3 ../gitlab_data.py
elif [[ ${git_system} == "2" ]]; then
    python3 ../github_data.py
fi

# run scheduled queries
for table in changes deployments incidents; do
    scheduled_query=$(bq ls --transfer_config --transfer_location=US | grep "four_keys_$table" -m 1 | awk '{print $1;}')
    bq mk --transfer_run --run_time "$(date --iso-8601=seconds)" $scheduled_query
done
