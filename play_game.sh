#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file.ni>"
    exit 1
fi

# Extract the base name from the argument (remove the .ni extension)
input_file="$1"
base_name="${input_file%.ni}"

# Step 1: Run Inform 7
echo "Running Inform 7..."
inform/inform7/Tangled/inform7 "$input_file"

# Check if Inform 7 was successful
if [ $? -ne 0 ]; then
    echo "Inform 7 compilation failed."
    exit 1
fi

# Step 2: Run Inform 6 (remove .ni and add .i6)
i6_file="$base_name.i6"
echo "Running Inform 6..."
inform6/Tangled/inform6 -G -w "$i6_file"

# Check if Inform 6 was successful
if [ $? -ne 0 ]; then
    echo "Inform 6 compilation failed."
    exit 1
fi

# Step 3: Run Glulxe (using .ulx file)
ulx_file="$base_name.ulx"
echo "Running Glulxe..."
../glulxe/glulxe "$ulx_file"

# Check if Glulxe ran successfully
if [ $? -ne 0 ]; then
    echo "Glulxe failed to run the game."
    exit 1
fi

echo "Execution complete!"

