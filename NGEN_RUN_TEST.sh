#!/bin/bash

# Define necessary modules for loading
MODULES=(
  gnu12
  py3-numpy/1.19.5
  Anaconda3/2023.09
  Boost/1.81.0-GCC-12.2.0
  OpenMPI/4.1.4-GCC-12.2.0
  netCDF-C++4/4.3.1-gompi-2023a
  CMake/3.26.3-GCCcore-12.3.0
  cmake/3.24.2
)

# Load modules
for module in "${MODULES[@]}"; do
  module load "$module"
done

# Define the NGen executable and data directories
NGEN_DIR="/home/hjajula/NGEN_INSTALL/ngen/parallelbuild"
DATA_DIR="/home/hjajula/NGEN_INSTALL/ngen/data"

# Activate the Conda environment
source activate /home/hjajula/ngen/ngen/hjajula/.conda/envs/ngen_build

# Ensure libudunits2.so.0 and other shared libraries are found
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"

# Generate a new partition configuration
PARTITION_CONFIG="$DATA_DIR/partition_config_test.json"
PARTITION_NUM=8  # Adjust based on your testing needs

# Debugging partitionGenerator with GDB
if [ ! -f "$PARTITION_CONFIG" ]; then
    echo "Debugging partition generation with GDB..."
    gdb --batch --quiet -ex "run" -ex "bt" --args $NGEN_DIR/partitionGenerator $DATA_DIR/catchment_data.geojson $DATA_DIR/nexus_data.geojson $PARTITION_CONFIG $PARTITION_NUM "" ""
    if [ $? -eq 0 ]; then
        echo "Partition configuration generated successfully."
    else
        echo "Partition generation failed. Check GDB output above."
        exit 1
    fi
fi



# Choose the test case based on the partition configuration
echo "Running NGen with the new partition configuration..."

# Test Case: Subdivided Hydrofabric
mpirun -n $PARTITION_NUM $NGEN_DIR/ngen $DATA_DIR/catchment_data.geojson "" $DATA_DIR/nexus_data.geojson "" $DATA_DIR/example_realization_config.json $PARTITION_CONFIG --subdivided-hydrofabric

echo "NGen testing with new partition configuration completed."

