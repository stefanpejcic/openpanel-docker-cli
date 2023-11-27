#!/bin/bash
################################################################################
# Script Name: /usr/local/bin/opencli
# Description: Makes all OpenCLI commands available on the terminal.
# Usage: opencli <COMMAND-NAME>
# Author: Stefan Pejcic
# Created: 15.11.2023
# Last Modified: 15.11.2023
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

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <command>"
  exit 1
fi

# Define the directory containing the binaries
script_dir="/usr/local/admin/scripts"

# Get the command from the argument
command="$1"

# Replace '-' with '/' in the command
binary_command="${command//-//}"

# Build the full path to the binary
binary_path="$script_dir/$binary_command"

# Check if the binary exists and is executable
if [ -x "$binary_path" ]; then
  # Execute the binary
  "$binary_path"
else
  echo "Error: Binary '$binary_command' not found or not executable in '$script_dir'"
  exit 1
fi
