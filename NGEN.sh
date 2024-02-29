#!/bin/bash
#SBATCH --job-name=ngen_run                             # Job_name
#SBATCH --partition=normal                              # Partition
#SBATCH --nodelist=compute002                           # List the nodes
#SBATCH --ntasks=10                                     # Number of tasks per node
#SBATCH --time=24:00:00                                 # Time limit
#SBATCH --output=./output/ngen_%j.log                   # Output file

# ANSI color codes for colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Increase `ulimit` for open files
ulimit -n 10000

# Generate a unique name for the Conda environment using a timestamp
ENV_PREFIX="ngen_env_"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ENV_NAME="${ENV_PREFIX}${TIMESTAMP}"

echo -e "${CYAN}Creating a new Conda environment '${ENV_NAME}' from environment_setup.yml...${RESET}"
conda env create -f environment_setup.yml -n "${ENV_NAME}"
echo -e "${GREEN}Environment '${ENV_NAME}' created successfully.${RESET}"

# Activate the Conda environment
echo -e "${CYAN}Activating the Conda environment '${ENV_NAME}'...${RESET}"
conda activate "${ENV_NAME}"

# Determine and set the CONDA_PREFIX dynamically
CONDA_PREFIX=$(conda env list | grep "${ENV_NAME}" | awk '{print $2}')
echo -e "${CYAN}Conda environment prefix: $CONDA_PREFIX${RESET}"

# Load necessary modules (Commented out if not applicable or handled by Conda)
module load gnu12
module load py3-numpy/1.19.5
module load Anaconda3/2023.09
module load Boost/1.81.0-GCC-12.2.0
module load OpenMPI/4.1.4-GCC-12.2.0
module load netCDF-C++4/4.3.1-gompi-2023a
module load CMake/3.26.3-GCCcore-12.3.0
module load cmake/3.24.2

# Adjusting PATH and PYTHONPATH to ensure Python from the Conda environment is used
export PATH="$CONDA_PREFIX/bin:$PATH"
export PYTHONPATH="$CONDA_PREFIX/lib/python3.9/site-packages:$PYTHONPATH"

# Ensuring UDUNITS library is correctly found
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"

# Set BOOST_ROOT environment variable
export BOOST_ROOT="$CONDA_PREFIX"

# Remove existing ngen directory if it exists
echo -e "${YELLOW}Checking for existing ngen directory and removing if exists...${RESET}"
if [ -d "ngen" ]; then
    rm -rf ngen
    echo -e "${GREEN}Removed existing ngen directory.${RESET}"
fi

echo -e "${CYAN}LOAD NGEN FROM GIT${RESET}"
echo "========================================="
git clone https://github.com/NOAA-OWP/ngen.git
cd ngen
git submodule update --init --recursive -- test/googletest
git submodule update --init --recursive -- extern/pybind11
git submodule update --init --recursive --depth 1
NGEN_BASE_DIR=$(pwd)

echo -e "${CYAN}NGEN BASE directory is: $NGEN_BASE_DIR${RESET}"
echo "========================================="
cd ./extern/
NGEN_EXTERN_DIR=$(pwd)
echo "========================================="
# Function to handle each external module build
build_module() {
    local module_name=$1
    local cmake_target=$2
    echo -e "${GREEN}BUILDING $module_name${RESET}"
    cd "$NGEN_EXTERN_DIR/$module_name"
    if "$CONDA_PREFIX/bin/cmake" -B cmake_build -S . && "$CONDA_PREFIX/bin/cmake" --build cmake_build --target $cmake_target -- -j 10; then
        echo -e "${GREEN}Successfully built $module_name.${RESET}"
    else
        echo -e "${RED}Failed to build $module_name. Skipping...${RESET}"
    fi
    cd "$NGEN_EXTERN_DIR"
    echo "========================================="
    echo ""
}

# Build external modules
for module in bmi-cxx cfe iso_c_fortran_bmi netcdf-cxx4 pybind11 SoilFreezeThaw SoilMoistureProfiles test_bmi_c test_bmi_cpp test_bmi_fortran test_bmi_py topmodel; do
    build_module $module "all"
done


cd "$NGEN_BASE_DIR"

# Configure and build NGen in serial mode with detailed configuration options
echo -e "${CYAN}Configuring and building NGen in serial mode with detailed options...${RESET}"
mkdir -p serialbuild && cd serialbuild
"$CONDA_PREFIX/bin/cmake" .. -DCMAKE_EXE_LINKER_FLAGS="-L$CONDA_PREFIX/lib" \
-DNGEN_MPI_ACTIVE=OFF \
-DNGEN_ACTIVATE_PYTHON=ON \
-DNGEN_WITH_SQLITE=ON \
-DSQLite3_INCLUDE_DIR="$CONDA_PREFIX/include" \
-DSQLite3_LIBRARY="$CONDA_PREFIX/lib/libsqlite3.so" \
-DNGEN_WITH_NETCDF=ON \
-DNGEN_WITH_UDUNITS=ON \
-DNGEN_WITH_BMI_FORTRAN=ON \
-DNGEN_WITH_BMI_C=ON \
-DNGEN_WITH_PYTHON=ON \
-DNGEN_WITH_ROUTING=ON \
-DNGEN_WITH_TESTS=ON \
-DNGEN_QUIET=ON \
-DCMAKE_BUILD_TYPE=Release \
-B . -S ..
make -j 10
echo -e "${GREEN}NGen serial build complete.${RESET}"
cd ..

# Configure and build NGen in parallel mode with detailed configuration options
echo -e "${CYAN}Configuring and building NGen in parallel mode with detailed options...${RESET}"
mkdir -p parallelbuild && cd parallelbuild
"$CONDA_PREFIX/bin/cmake" .. -DCMAKE_EXE_LINKER_FLAGS="-L$CONDA_PREFIX/lib" \
-DNGEN_MPI_ACTIVE=ON \
-DNGEN_ACTIVATE_PYTHON=ON \
-DNGEN_WITH_SQLITE=ON \
-DSQLite3_INCLUDE_DIR="$CONDA_PREFIX/include" \
-DSQLite3_LIBRARY="$CONDA_PREFIX/lib/libsqlite3.so" \
-DNGEN_WITH_NETCDF=ON \
-DNGEN_WITH_UDUNITS=ON \
-DNGEN_WITH_BMI_FORTRAN=ON \
-DNGEN_WITH_BMI_C=ON \
-DNGEN_WITH_PYTHON=ON \
-DNGEN_WITH_ROUTING=ON \
-DNGEN_WITH_TESTS=ON \
-DNGEN_QUIET=ON \
-DCMAKE_BUILD_TYPE=Release \
-B . -S ..
make -j 10
echo -e "${GREEN}NGen parallel build complete.${RESET}"


# Run the NGen tests

# Run the serial tests
if [ -d "$NGEN_BASE_DIR/serialbuild" ]; then
    echo "Running serial tests..."
    # Change to your serial build directory and execute tests
else
    echo "Error: Serial build directory does not exist."
fi

# Run the parallel tests
if [ -d "$NGEN_BASE_DIR/parallelbuild" ]; then
    echo "Running parallel tests..."
    # Change to your parallel build directory and execute tests
else
    echo "Error: Parallel build directory does not exist."
fi

# Running MPI tests manually, adjust the path to your test executable
if [ -f "$NGEN_BASE_DIR/parallelbuild/test/test_remote_nexus" ]; then
    echo "Running MPI tests manually..."
    mpirun -n 2 "$NGEN_BASE_DIR/parallelbuild/test/test_remote_nexus" > "$NGEN_BASE_DIR/test_output_2np.txt"
    mpirun -n 3 "$NGEN_BASE_DIR/parallelbuild/test/test_remote_nexus" > "$NGEN_BASE_DIR/test_output_3np.txt"
    mpirun -n 4 "$NGEN_BASE_DIR/parallelbuild/test/test_remote_nexus" > "$NGEN_BASE_DIR/test_output_4np.txt"
    echo "MPI tests completed."
else
    echo "Executable test_remote_nexus not found."
fi

# Clean up test artifacts not needed
find parallelbuild -type f ! \( -name "*.so" -o -name "ngen" -o -name "partitionGenerator" \) -exec rm {} +


# Number of partitions for parallel execution
PARTITION_NUM=10

# Download and extract AWI_03W_113060_003 data
DATA_DOWNLOAD_DIR="$NGEN_BASE_DIR/AWI_DATA"
mkdir -p "$DATA_DOWNLOAD_DIR"
AWI_DATA_URL="https://ciroh-ua-ngen-data.s3.us-east-2.amazonaws.com/AWI-003/AWI_03W_113060_003.tar.gz"
AWI_DATA_TAR="${DATA_DOWNLOAD_DIR}/AWI_03W_113060_003.tar.gz"
AWI_DATA_DIR="${DATA_DOWNLOAD_DIR}/AWI_03W_113060_003"

echo "Downloading AWI_03W_113060_003 data..."
wget --no-parent -O "${AWI_DATA_TAR}" "${AWI_DATA_URL}"

echo "Extracting data..."
mkdir -p "${AWI_DATA_DIR}"
tar -xf "${AWI_DATA_TAR}" -C "${AWI_DATA_DIR}" --strip-components=1

# Update DATA_DIR and CONFIG_DIR to use the downloaded and extracted data
DATA_DIR="${AWI_DATA_DIR}"
CONFIG_DIR="${AWI_DATA_DIR}/config"

# Define the partitionGenerator and ngen executables location using NGEN_BASE_DIR
NGEN_SERIAL="$NGEN_BASE_DIR/serialbuild/ngen"
NGEN_PARALLEL="$NGEN_BASE_DIR/parallelbuild/ngen"
PARTITIONGEN_SERIAL="$NGEN_BASE_DIR/serialbuild/partitionGenerator"
PARTITIONGEN_PARALLEL="$NGEN_BASE_DIR/parallelbuild/partitionGenerator"

# Check if partitionGenerator and ngen executables exist
if [ ! -f "$PARTITIONGEN_PARALLEL" ]; then
    echo "partitionGenerator not found at $PARTITIONGEN_PARALLEL. Please check your NGen build."
    exit 1
fi

if [ ! -f "$NGEN_PARALLEL" ]; then
    echo "NGen executable not found at $NGEN_PARALLEL. Please check your NGen build."
    exit 1
fi


# Define paths to the AWI dataset config files for parallel testing
CATCHMENT_DATA_PATH="${CONFIG_DIR}/catchments.geojson"
NEXUS_DATA_PATH="${CONFIG_DIR}/nexus.geojson"
REALIZATION_CONFIG_PATH="${CONFIG_DIR}/awi_simplified_realization.json"
PARTITION_CONFIG_PATH="${CONFIG_DIR}/AWI_003_10partitions.json"

# Generate Partition Configuration if not exists
if [ ! -f "$CONFIG_DIR/$OUTPUT_PARTITION_CONFIG" ]; then
    echo "Generating partition configuration..."
    $PARTITIONGEN_PARALLEL "${CONFIG_DIR}/catchments.geojson" "${CONFIG_DIR}/nexus.geojson" "$CONFIG_DIR/$OUTPUT_PARTITION_CONFIG" $PARTITION_NUM '' ''
    echo "Partition configuration generated at $CONFIG_DIR/$OUTPUT_PARTITION_CONFIG."
else
    echo "Using existing partition configuration at $CONFIG_DIR/$OUTPUT_PARTITION_CONFIG."
fi

# Run the serial test for the AWI dataset
echo "Running serial test for AWI dataset..."
$NGEN_SERIAL "${CONFIG_DIR}/catchments.geojson" "" "${CONFIG_DIR}/nexus.geojson" "" "${CONFIG_DIR}/awi_simplified_realization.json"
echo "Serial test for AWI dataset completed."

# Run the parallel test for the AWI dataset
echo "Running NGen with MPI for AWI003 data..."
mpirun -n $PARTITION_NUM $NGEN_PARALLEL "${CONFIG_DIR}/catchments.geojson" "all" "${CONFIG_DIR}/nexus.geojson" "all" "${CONFIG_DIR}/awi_simplified_realization.json" "$CONFIG_DIR/$OUTPUT_PARTITION_CONFIG"
echo "NGen AWI003 run completed."
