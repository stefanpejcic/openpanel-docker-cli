#!/bin/bash
################################################################################
# Script Name: user/delete.sh
# Description: Delete user account and permanently remove all their data.
# Usage: opencli user-delete <USERNAME> [-y]
# Author: Stefan Pejcic
# Created: 01.10.2023
# Last Modified: 22.08.2024
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

# Check if the correct number of command-line arguments is provided
if [ "$#" -ne 1 ] && [ "$#" -ne 2 ]; then
    echo "Usage: opencli user-delete <username> [-y]"
    exit 1
fi



# Get username from a command-line argument
username="$1"

# Check if the -y flag is provided to skip confirmation
if [ "$#" -eq 2 ] && [ "$2" == "-y" ]; then
    skip_confirmation=true
else
    skip_confirmation=false
fi

# Function to confirm actions with the user
confirm_action() {
    if [ "$skip_confirmation" = true ]; then
        return 0
    fi

    read -r -p "This will permanently delete user '$username' and all of its data from the server. Please confirm [Y/n]: " response
    response=${response,,} # Convert to lowercase
    if [[ $response =~ ^(yes|y| ) ]]; then
        return 0
    else
        echo "Operation canceled."
        exit 0
    fi
}

# DB
source /usr/local/admin/scripts/db.sh



get_docker_context_for_user(){
    # GET CONTEXT NAME FOR DOCKER COMMANDS
    server_name=$(mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "SELECT server FROM users WHERE username='$username';" -N)
    
    if [ -z "$server_name" ]; then
        server_name="default" # compatibility with older panel versions before clustering
        context_flag=""
        node_ip_address=""
    elif [ "$server_name" == "default" ]; then
        context_flag=""
        node_ip_address=""
    else
        context_flag="--context $server_name"
        # GET IPV4 FOR SSH COMMANDS
        context_info=$(docker context ls --format '{{.Name}} {{.DockerEndpoint}}' | grep "$server_name")
    
        if [ -n "$context_info" ]; then
            endpoint=$(echo "$context_info" | awk '{print $2}')
            if [[ "$endpoint" == ssh://* ]]; then
                node_ip_address=$(echo "$endpoint" | cut -d'@' -f2 | cut -d':' -f1)
            else
                echo "ERROR: valid IPv4 address for context $server_name not found!"
                echo "       User container is located on node $server_name and there is a docker context with the same name but it has no valid IPv4 in the endpoint."
                echo "       Make sure that the docker context named $server_nam has valid IPv4 address in format: 'SERVER ssh://USERNAME@IPV4' and that you can establish ssh connection using those credentials."
                exit 1
            fi
        else
            echo "ERROR: docker context with name $server_name does not exist!"
            echo "       User container is located on node $server_name but there is no docker context with that name."
            echo "       Make sure that the docker context exists and is available via 'docker context ls' command."
            exit 1
        fi
        
    fi



    # context         - node name
    # context_flag    - docker context to use in docker commands
    # node_ip_address - ipv4 to use for ssh
    
}


# Function to remove Docker container and all user files
remove_docker_container_and_volume() {
    docker $context_flag stop "$username"  2>/dev/null
    docker $context_flag rm "$username"  2>/dev/null
}


get_userid_from_db() {
    # Get the user_id from the 'users' table
    user_id=$(mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "SELECT id FROM users WHERE username='$username';" -N)

    if [ -z "$user_id" ]; then
        echo "ERROR: User '$username' not found in the database."
        exit 1
    fi
}


# TODO: delete on remote nginx server!

# Delete all users domains vhosts files from Nginx
delete_vhosts_files() {

    # Get all domain_names associated with the user_id from the 'domains' table
    domain_names=$(mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "SELECT domain_name FROM domains WHERE user_id='$user_id';" -N)

    # Disable Nginx virtual hosts, delete SSL and configuration files for each domain
    for domain_name in $domain_names; do

       if [ -d "/etc/live/letsencrypt/$domain_name" ]; then
            echo "revoking and deleting existing Let's Encrypt certificate"
            docker $context_flag exec certbot sh -c "certbot revoke -n --cert-name $domain_name"
            docker $context_flag exec certbot sh -c "certbot delete -n --cert-name $domain_name"           
        else
            # TODO: delete paid SSLs also!
            echo "Doman had no Let's Encrypt certificate"
        fi

        echo "Deleting files /etc/nginx/sites-available/$domain_name.conf and /etc/nginx/sites-enabled/$domain_name.conf"
    
        if [ -n "$node_ip_address" ]; then
            # TODO: INSTEAD OF ROOT USER SSH CONFIG OR OUR CUSTOM USER!
            ssh "root@$node_ip_address" "rm /etc/nginx/sites-available/$domain_name.conf && rm /etc/nginx/sites-enabled/$domain_name.conf"
        else
            rm /etc/nginx/sites-available/$domain_name.conf
            rm /etc/nginx/sites-enabled/$domain_name.conf
        fi

    done

    # TODO: RUN THIS ON REMOTE SERVER!
    
    # Reload Nginx to apply changes
    opencli server-recreate_hosts  > /dev/null 2>&1
    docker $context_flag exec nginx bash -c "nginx -t && nginx -s reload"  > /dev/null 2>&1

    echo "SSL Certificates, Nginx Virtual hosts and configuration files for all of user '$username' domains deleted successfully."
}

# Function to delete user from the database
delete_user_from_database() {

    # Step 1: Get the user_id from the 'users' table
    user_id=$(mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "SELECT id FROM users WHERE username='$username';" -N)
    
    if [ -z "$user_id" ]; then
        echo "Error: User '$username' not found in the database."
        exit 1
    fi

    # Step 2: Get all domain_ids associated with the user_id from the 'domains' table
    domain_ids=$(mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "SELECT domain_id FROM domains WHERE user_id='$user_id';" -N)

    # Step 3: Delete rows from the 'sites' table based on the domain_ids
    for domain_id in $domain_ids; do
        mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "DELETE FROM sites WHERE domain_id='$domain_id';"
    done

    # Step 4: Delete rows from the 'domains' table based on the user_id
    mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "DELETE FROM domains WHERE user_id='$user_id';"

    # Step 5: Delete the user_id from the 'active_sessions' table
    mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "DELETE FROM active_sessions WHERE user_id='$user_id';"

    # Step 6: Delete the user from the 'users' table
    mysql --defaults-extra-file=$config_file -D "$mysql_database" -e "DELETE FROM users WHERE username='$username';"

    echo "User '$username' and associated data deleted from MySQL database successfully."
}



delete_ftp_users() {
    openpanel_username="$1"
    users_dir="/etc/openpanel/ftp/users"
    users_file="${users_dir}/${openpanel_username}/users.list"

    # Check if the users file exists
    if [[ -f "$users_file" ]]; then
        echo "Checking and removing user's FTP sub-accounts"
        # Loop through each line in the users.list file
        while IFS='|' read -r username password directories; do
            # Run the opencli command for each username
            echo "Deleting FTP user: $username"
            opencli ftp-delete "$username" "$openpanel_username"
        done < "$users_file"
    fi
}


# Function to disable UFW rules for ports containing the username
disable_ports_in_ufw() {
  line_numbers=$(ufw status numbered | awk -F'[][]' -v user="$username" '$NF ~ " " user "$" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' |sort -rn)

  for line_number in $line_numbers; do
    yes | ufw delete $line_number
    echo "Deleted rule #$line_number"
  done
}


# Function to delete bandwidth limit settings for a user
delete_bandwidth_limits() {

        ip_address=$(docker $context_flag container inspect -f '{{ .NetworkSettings.IPAddress }}' "$username")
        if [ -n "$node_ip_address" ]; then
            # TODO: INSTEAD OF ROOT USER SSH CONFIG OR OUR CUSTOM USER!
            ssh "root@$node_ip_address" "tc qdisc del dev docker0 root && tc class del dev docker0 parent 1: classid 1:1 && tc filter del dev docker0 parent 1: protocol ip prio 16 u32 match ip dst $ip_address"
        else
              tc qdisc del dev docker0 root 2>/dev/null
              tc class del dev docker0 parent 1: classid 1:1 2>/dev/null
              tc filter del dev docker0 parent 1: protocol ip prio 16 u32 match ip dst "$ip_address" 2>/dev/null
        fi
}

edit_firewall_rules(){
    # CSF
    if command -v csf >/dev/null 2>&1; then
        FIREWALL="CSF"
        container_ports=("22" "3306" "7681" "8080")
        #we use range, so not need to rm rules for account delete..
    
    # UFW
    elif command -v ufw >/dev/null 2>&1; then
        FIREWALL="UFW"
        disable_ports_in_ufw
        ufw reload
    fi
}


delete_all_user_files() {
        if [ -n "$node_ip_address" ]; then
            # TODO: INSTEAD OF ROOT USER SSH CONFIG OR OUR CUSTOM USER!
            ssh "root@$node_ip_address" "umount /home/storage_file_$username && rm -rf /home/$username && rm -rf /home/storage_file_$username"
            ssh "root@$node_ip_address" "sed -i.bak '/\/home\/storage_file_$old_username \/home\/$old_username ext4 loop 0 0/d' /etc/fstab"   # on slave
            sed -i.bak "/\/home\/$old_username \/home\/$old_username fuse.sshfs defaults,_netdev,allow_other 0 0/d" /etc/fstab                # on master
        else
            umount /home/storage_file_$username > /dev/null 2>&1
            rm -rf /home/$username > /dev/null 2>&1
            rm -rf /home/storage_file_$username  > /dev/null 2>&1
            sed -i.bak "/\/home\/storage_file_$old_username \/home\/$old_username ext4 loop 0 0/d" /etc/fstab > /dev/null 2>&1                # only on master
        fi

        rm -rf /etc/openpanel/openpanel/core/stats/$username
        rm -rf /etc/openpanel/openpanel/core/users/$username
}









# MAIN EXECUTION
confirm_action                           # yes
get_userid_from_db                       # check if user exists
get_docker_context_for_user              # on which server is the container running
delete_vhosts_files                      # delete nginx conf files from that server
edit_firewall_rules                      # close user ports on firewall
delete_bandwidth_limits                  # delete bandwidth limits for private ip
remove_docker_container_and_volume       # delete contianer and all docker files
delete_ftp_users $username
delete_user_from_database                # delete user from database
delete_all_user_files                    # permanently delete data
echo "User $username deleted."           # if we made it
