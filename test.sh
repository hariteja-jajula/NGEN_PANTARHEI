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

# Define the name for the Conda environment
ENV_NAME="ngen_env"
conda init

echo -e "${CYAN}Checking for the Conda environment '${ENV_NAME}'...${RESET}"
if ! conda info --envs | grep "${ENV_NAME}"; then
    echo -e "${YELLOW}Environment '${ENV_NAME}' not found. Creating from environment_setup.yml...${RESET}"
    conda env create -f environment_setup.yml -n "${ENV_NAME}"
    echo -e "${GREEN}Environment '${ENV_NAME}' created successfully.${RESET}"
else
    echo -e "${GREEN}Environment '${ENV_NAME}' already exists. Proceeding with activation.${RESET}"
fi

# Activate the Conda environment
echo -e "${CYAN}Activating the Conda environment '${ENV_NAME}'...${RESET}"
conda activate "${ENV_NAME}"

# Determine and set the CONDA_PREFIX dynamically
CONDA_PREFIX=$(conda env list | grep "\b${ENV_NAME}\b" | awk '{print $2}')
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
    if cmake -B cmake_build -S . && cmake --build cmake_build --target $cmake_target -- -j 10; then
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
cmake .. -DCMAKE_EXE_LINKER_FLAGS="-L$CONDA_PREFIX/lib" \
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
cmake .. -DCMAKE_EXE_LINKER_FLAGS="-L$CONDA_PREFIX/lib" \
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

# Run the serial tests and remove output from previous test runs
echo -e "${CYAN}Running serial tests...${RESET}"
cmake --build serialbuild --target test
rm -f ./test/data/routing/*.parquet

# Run the parallel tests and clean up
echo -e "${CYAN}Running parallel tests...${RESET}"
cmake --build parallelbuild --target test
rm -f ./test/data/routing/*.parquet

# Run the MPI tests manually
echo -e "${CYAN}Running MPI tests manually...${RESET}"
mpirun -n 2 parallelbuild/test/test_remote_nexus
mpirun -n 3 parallelbuild/test/test_remote_nexus
mpirun -n 4 parallelbuild/test/test_remote_nexus

# Clean up test artifacts not needed
find parallelbuild -type f ! \( -name "*.so" -o -name "ngen" -o -name "partitionGenerator" \) -exec rm {} +
