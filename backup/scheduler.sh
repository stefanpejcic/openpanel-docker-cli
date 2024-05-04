#!/bin/bash
################################################################################
# Script Name: backup/scheduler.sh
# Description: Schedule backup jobs and execute them in time.
# Usage: opencli backup-schedule [--debug]
# Author: Stefan Pejcic
# Created: 02.02.2024
# Last Modified: 04.05.2024
# Company: openpanel.co
# Copyright (c) openpanel.co
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
################################################################################

DEBUG=false
run_id=""
json_dir="/usr/local/admin/backups/jobs/"

for arg in "$@"; do
    case $arg in
        --debug)
            DEBUG=true
            ;;
        --run=*)
            run_id="${arg#*=}"
            ;;
    esac
done

# Function to convert schedule to cron format
schedule_to_cron() {
    case "$1" in
        "hourly")   echo "0 * * * *";;
        "daily")    echo "0 1 * * *";;
        "weekly")   echo "0 1 * * SUN";;
        "monthly")  echo "0 0 1 * *";;
        *)          echo "ERROR: Invalid schedule value"; exit 1;;
    esac
}

# Function to determine flag based on type value
determine_flag() {
    local flags=""
    case "$1" in
        "configuration") flags="--conf";;
        "accounts")
            if [ -n "$2" ]; then
                IFS=' ' read -ra filter_array <<< "$2"
                for filter in "${filter_array[@]}"; do
                    flags+=" --$filter"
                done
            else
                flags="--all"
            fi
            ;;
        *)  echo "ERROR: Invalid type value"; exit 1;;
    esac
    echo "$flags"
}

# Main function to process backup jobs
process_backup_job() {
    local file="$1"
    local schedule=$(jq -r '.schedule' "$file")
    local destination=$(jq -r '.destination' "$file")
    local type=$(jq -r '.type | .[]' "$file")
    local filters=$(jq -r '.filters | map(. + "") | join(" ")' "$file")
    local flag=$(determine_flag "$type" "$filters")

    if [ -z "$run_id" ]; then
        local cron_schedule=$(schedule_to_cron "$schedule")
        if [ "$DEBUG" = true ]; then
            printf "%s %s %s %s\n" "$cron_schedule" "opencli backup-run $(basename "$file" .json)" "$flag" >> /etc/crontab
            printf "%s %s %s %s\n" "$cron_schedule" "opencli backup-run $(basename "$file" .json)" "$flag"
        else
            printf "%s %s %s %s\n" "$cron_schedule" "opencli backup-run $(basename "$file" .json)" "$flag" >> /etc/crontab
        fi
    else
        echo "opencli backup-run $(basename "$file" .json)" "$flag"
    fi
}


# Remove previous backup schedules
sed -i '/opencli backup-run/d' /etc/crontab

# Process one job if run_id is provided, otherwise process and schedule all jobs
if [ "$run_id" ]; then
    file="/usr/local/admin/backups/jobs/$run_id.json"
    if [ -f "$file" ]; then
        process_backup_job "$file"
    else
        echo "ERROR: JSON file '$run_id.json' not found."
        exit 1
    fi
else
    for file in /usr/local/admin/backups/jobs/*.json; do
        if [ -f "$file" ] && jq -e '.status == "on"' "$file" >/dev/null; then
            process_backup_job "$file"
        fi
    done
fi
