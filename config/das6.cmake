set(ENV{CC}  gcc ) # C compiler for parallel build
set(ENV{CXX} g++) # C++ compiler for serial build

set(USER_CXX_FLAGS "-std=c++14 -fopenmp")
set(USER_CXX_FLAGS_RELEASE "-DNDEBUG -O3 -march=native")
add_definitions(-DRESTRICTKEYWORD=__restrict__)

set(USER_CXX_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")

# NetCDF/HDF5/Boost are located via find_package() in the top-level
# CMakeLists.txt; these EasyBuild module prefixes are not on CMake's default
# search path, so they're passed as hints. (FFTW/IRC dropped: nothing in
# this codebase calls either directly, they were unused link inputs.)
list(APPEND CMAKE_PREFIX_PATH
  "/opt/ohpc/pub/libs/gnu9/openmpi4/netcdf/4.7.3"
  "/opt/ohpc/pub/libs/gnu9/openmpi4/hdf5/1.10.6"
  "/opt/ohpc/pub/libs/gnu9/openmpi4/boost/1.73.0")

set(LIBS "")

if(RTE_USE_CUDA)
    set(LIBS ${LIBS} -rdynamic)
    # Previously set via USER_CUDA_NVCC_FLAGS / CUDA_NVCC_FLAGS, which are
    # FindCUDA-module variables the top-level CMakeLists.txt never reads
    # (it uses native CUDA-language support and reads USER_CUDA_FLAGS) --
    # meaning these flags were silently never applied. Fixed here.
    set(USER_CUDA_FLAGS "-std=c++14 -arch=sm_80 --expt-relaxed-constexpr")
endif()

add_definitions(-DRTE_USE_CBOOL)