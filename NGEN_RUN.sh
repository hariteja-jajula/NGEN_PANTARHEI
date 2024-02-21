#!/bin/bash
#SBATCH --job-name=ngen_run                             # Job_name
#SBATCH --partition=normal                              # Partition
#SBATCH --nodelist=compute002                           # List the nodes
#SBATCH --ntasks=10                                     # Number of tasks per node
#SBATCH --time=24:00:00                                 # Time limit
#SBATCH --output=./output/ngen_run_%j.log               # Output file

# ANSI color codes for colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Load necessary modules
module load gnu12
module load py3-numpy/1.19.5
module load Anaconda3/2023.09
module load Boost/1.81.0-GCC-12.2.0
module load OpenMPI/4.1.4-GCC-12.2.0
module load netCDF-C++4/4.3.1-gompi-2023a
module load CMake/3.26.3-GCCcore-12.3.0
module load cmake/3.24.2

# Define the directory where NGen and partitionGenerator are located
NGEN_DIR="/home/hjajula/NGEN_INSTALL/ngen/parallelbuild"

# Activate the Conda environment and ensure libudunits2.so.0 is found
source activate /home/hjajula/ngen/ngen/hjajula/.conda/envs/ngen_build

# Adjust LD_LIBRARY_PATH to include the lib directory of the Conda environment
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"

# Define data and configuration directories
DATA_DIR="/home/hjajula/ngen-data"
CONFIG_DIR="/home/hjajula/ngen-data/ngen-run/config"

# Number of partitions for parallel execution
PARTITION_NUM=10

# Check if partitionGenerator and ngen executables exist
PARTITION_GENERATOR="$NGEN_DIR/partitionGenerator"
NGEN_EXECUTABLE="$NGEN_DIR/ngen"

if [ ! -f "$PARTITION_GENERATOR" ]; then
    echo "partitionGenerator not found at $PARTITION_GENERATOR. Please check your NGen build."
    exit 1
fi

if [ ! -f "$NGEN_EXECUTABLE" ]; then
    echo "NGen executable not found at $NGEN_EXECUTABLE. Please check your NGen build."
    exit 1
fi

# Generate Partition Configuration if not exists
if [ ! -f "$CONFIG_DIR/partition_config.json" ]; then
    echo "Generating partition configuration..."
    $PARTITION_GENERATOR $DATA_DIR/conus.gpkg $DATA_DIR/conus.gpkg $CONFIG_DIR/partition_config.json $PARTITION_NUM '' ''
    echo "Partition configuration generated at $CONFIG_DIR/partition_config.json."
else
    echo "Using existing partition configuration at $CONFIG_DIR/partition_config.json."
fi

# Run NGen with MPI
echo "Running NGen with MPI..."
mpirun -n $PARTITION_NUM $NGEN_EXECUTABLE $DATA_DIR/conus.gpkg all $DATA_DIR/conus.gpkg all $CONFIG_DIR/realization.json $CONFIG_DIR/partition_config.json
echo "NGen run completed."

