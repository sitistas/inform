#!/bin/bash

set -e
# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file.ni>"
    exit 1
fi

# Extract the base name from the argument (remove the .ni extension)
input_file="$1"
base_name="${input_file%.ni}"

run_inform7() {
    echo "Running Inform 7..."
    inform7/Tangled/inform7 "$input_file"
    echo "Inform 7 compilation successful."
}

run_inform6() {
    i6_file="$base_name.i6"
    echo "Running Inform 6..."
    inform6/Tangled/inform6 -G -w "$i6_file"
    echo "Inform 6 compilation successful."
}

run_glulxe() {
    ulx_file="$base_name.ulx"
    echo "Running Glulxe..."
    ../glulxe/glulxe "$ulx_file"
    echo "Glulxe ran the game successfully."
}

run_inform7
run_inform6
run_glulxe

echo "Execution complete!"