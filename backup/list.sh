#!/bin/bash




# Function to print output in JSON format
print_json() {
    local backup_job_id=$1
    local username=$2
    local index_files=$3

    cat <<EOF
{
  "job": "$backup_job_id",
  "username": "$username",
  "date": [$index_files]
}
EOF
}


DEBUG=false
JSON_FLAG=false

for arg in "$@"; do
    case $arg in
        --debug)
            DEBUG=true
            ;;
        --json)
            JSON_FLAG=true
            DEBUG=false
            ;;
    esac
done


# Check if the correct number of command line arguments is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: opencli backup-list <USERNAME>"
    exit 1
fi


USERNAME=$1
SEARCH_DIR="/usr/local/admin/backups/index"

# Check if the main directory exists
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Main directory not found: $SEARCH_DIR"
    exit 1
fi

# Find folders with the provided username
user_folders=$(find "$SEARCH_DIR" -type d -name "$USERNAME")

# Check if any matching folders are found
if [ -z "$user_folders" ]; then
    echo "No folders found for user: $USERNAME"
    exit 1
fi

# Variable to accumulate JSON output
json_output=""

# Iterate through each matching folder
for folder in $user_folders; do
    # Extract Backup job ID and Username from the directory path
    backup_job_id=$(echo "$folder" | awk -F'/' '{print $(NF-1)}')
    username=$(echo "$folder" | awk -F'/' '{print $NF}')

    # List .index files in the current folder
    index_files=$(find "$folder" -type f -name "*.index" -exec basename {} \; | sed 's/\.index$//' | paste -sd ',' -)

    # Check if --json option is passed and append to JSON output
    if $JSON_FLAG; then
        json_output+=$(print_json "$backup_job_id" "$username" "$index_files")
        json_output+=","
    else
        echo "Backup job ID: $backup_job_id"
        echo "Username: $username"

        # Check if any .index files are found
        if [ -z "$index_files" ]; then
            echo "No backups found under job id: $folder"
        else
            echo "Dates: $index_files"
        fi

        echo "-----------------------------"
    fi
done

# Remove the trailing comma in JSON output if present
json_output=${json_output%,}

# Print the accumulated JSON output
if $JSON_FLAG; then
    echo "[$json_output]"
fi
