#!/bin/bash
################################################################################
# Script Name: ssl/domain.sh
# Description: Generate or Delete SSL for a domain.
# Usage: opencli ssl-domain [-d] <domain_url>
# Author: Radovan Ječmenica
# Created: 27.11.2023
# Last Modified: 20.05.2024
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

#!/bin/bash
# Function to print usage information
print_usage() {
    echo "Usage: $0 [-d] <domain_url>"
    echo "Options:"
    echo "  -d     Delete SSL for the specified domain"
    echo "  <domain_url>   Domain URL for SSL operations"
}

get_server_ip() {
    # Your command
    domain_url=$1
    result=$(opencli domains-whoowns $domain_url)

    if [[ $result == *"Owner of"* ]]; then
        username=$(echo $result | awk '{print $NF}')
    else
        echo "rezultat: $result"
        exit 1
    fi

    #echo "Username: $username"

    current_username=$username
    dedicated_ip_file_path="/etc/openpanel/openpanel/core/users/{current_username}/ip.json"

    if [ -e "$dedicated_ip_file_path" ]; then
        # If the file exists, read the IP from it
        server_ip=$(jq -r '.ip' "$dedicated_ip_file_path" 2>/dev/null)
    else
        # Try to get the server's IP using the hostname -I command
        server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    #echo $server_ip
}

ensure_jq_installed() {
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        # Install jq using apt
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y -qq jq > /dev/null 2>&1
        # Check if installation was successful
        if ! command -v jq &> /dev/null; then
            echo "Error: jq installation failed. Please install jq manually and try again."
            exit 1
        fi
    fi
}

# Function to generate SSL
generate_ssl() {
    domain_url=$1

    echo "Generating SSL for domain: $domain_url"
    
    # Certbot command for SSL generation
    certbot_command=("python3" "/usr/bin/certbot" "certonly" "--nginx" "--non-interactive" "--agree-tos" "-m" "webmaster@$domain_url" "-d" "$domain_url")

    # Run Certbot command
    "${certbot_command[@]}"
    echo "SSL generation completed successfully"

    #trigger file reload and recheck all other domains also!
    opencli ssl-user $current_username  > /dev/null 2>&1

}

# Function to modify Nginx configuration
modify_nginx_conf() {
    domain_url=$1
    # Nginx configuration path
    nginx_conf_path="/etc/nginx/sites-available/$domain_url.conf"

    echo "Modifying Nginx configuration for domain: $domain_url"

    # Nginx configuration content to be added
    nginx_config_content="
    if (\$scheme != \"https\"){
        #return 301 https://\$host\$request_uri;
    } #forceHTTPS

    listen $server_ip:443 ssl http2;
    server_name $domain_url;
    ssl_certificate /etc/letsencrypt/live/$domain_url/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_url/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    "

    # Find the position of the last closing brace
    last_brace_position=$(awk '/\}/{y=x; x=NR} END{print y}' "$nginx_conf_path")

    # Insert the Nginx configuration content before the last closing brace
    awk -v content="$nginx_config_content" -v pos="$last_brace_position" 'NR == pos {print $0 ORS content; next} {print}' "$nginx_conf_path" > temp_file
    mv temp_file "$nginx_conf_path"

    echo "Nginx configuration modification completed successfully"
}

# Function to check if SSL is valid
check_ssl_validity() {
    domain_url=$1

    echo "Checking SSL validity for domain: $domain_url"

    # Certbot command to check SSL validity
    certbot_check_command=("python3" "/usr/bin/certbot" "certificates" "--non-interactive" "--cert-name" "$domain_url")

    # Run Certbot command to check SSL validity
    if "${certbot_check_command[@]}" | grep -q "Expiry Date:.*VALID"; then
        echo "SSL is valid. Exiting script."
        exit 0
    else
        echo "SSL is not valid. Proceeding with SSL generation."
    fi
}

# Function to delete SSL
delete_ssl() {
    domain_url=$1

    echo "Deleting SSL for domain: $domain_url"

    # Certbot delete command
    delete_command=("python3" "/usr/bin/certbot" "delete" "--cert-name" "$domain_url" "--non-interactive")

    # Run Certbot delete command
    "${delete_command[@]}"

    echo "SSL deletion completed successfully"
}
# Function to revert Nginx configuration
revert_nginx_conf() {
    domain_url=$1

    # Nginx configuration path
    nginx_conf_path="/etc/nginx/sites-available/$domain_url.conf"

    echo "Reverting Nginx configuration for domain: $domain_url"

    # Use sed to remove the added content from the Nginx configuration file
    sed -i '/if (\$scheme != "https"){/,/ssl_dhparam \/etc\/letsencrypt\/ssl-dhparams.pem;/d' "$nginx_conf_path"

    echo "Nginx configuration reversion completed successfully"
}

# Main script

# Check the number of arguments
if [ "$#" -lt 1 ]; then
    print_usage
    exit 1
fi

# Parse options
while getopts ":d" opt; do
    case $opt in
        d)
            delete_flag=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            print_usage
            exit 1
            ;;
    esac
done

# Remove options from the argument list
shift "$((OPTIND-1))"

# Get the domain URL
domain_url=$1

# Check if domain URL is provided
if [ -z "$domain_url" ]; then
    echo "Error: Domain URL is missing"
    print_usage
    exit 1
fi



# Perform actions based on options
if [ "$delete_flag" = true ]; then
    delete_ssl "$domain_url"
    revert_nginx_conf "$domain_url"
else
    # Generate SSL only if the check passed
    check_ssl_validity "$domain_url"
    ensure_jq_installed
    get_server_ip "$domain_url"
    generate_ssl "$domain_url" || exit 1
    modify_nginx_conf "$domain_url"
fi
