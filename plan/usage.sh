#!/bin/bash
################################################################################
# Script Name: usage.sh
# Description: Display all users that are currently using the plan.
# Usage: opencli plan-usage [--json]
# Docs: https://docs.openpanel.co/docs/admin/scripts/plans#list-users-on-plan
# Author: Stefan Pejcic
# Created: 30.11.2023
# Last Modified: 30.11.2023
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


# Function to print usage instructions
print_usage() {
    script_name=$(basename "$0")
    echo "Usage: $script_name <plan_name> [--json]"
    exit 1
}

# Initialize variables
json_output=false
plan_name=""

# Command-line argument processing
if [ "$#" -lt 1 ]; then
    print_usage
fi

plan_name=$1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            json_output=true
            shift
            ;;
        *)
            print_usage
            ;;
    esac
done

# Source database configuration
source /usr/local/admin/scripts/db.sh

# Fetch user data based on the provided plan name
if [ "$json_output" = true ]; then
    users_data=$(mysql --defaults-extra-file="$config_file" -D "$mysql_database" -e "SELECT users.id, users.username, users.email, plans.name AS plan_name, users.registered_date FROM users INNER JOIN plans ON users.plan_id = plans.id WHERE plans.name = '$plan_name';" | tail -n +2)
    if [ -n "$users_data" ]; then
        json_output=$(echo "$users_data" | jq -R 'split("\n") | map(split("\t") | {id: .[0], username: .[1], email: .[2], plan_name: .[3], registered_date: .[4]})')
        echo "Users on plan '$plan_name':"
        echo "$json_output"
    else
        echo "No users on plan '$plan_name'."
    fi
else
    users_data=$(mysql --defaults-extra-file="$config_file" -D "$mysql_database" --table -e "SELECT users.id, users.username, users.email, plans.name AS plan_name, users.registered_date FROM users INNER JOIN plans ON users.plan_id = plans.id WHERE plans.name = '$plan_name';")
    if [ -n "$users_data" ]; then
        echo "$users_data"
    else
        echo "No users on plan '$plan_name'."
    fi
fi
