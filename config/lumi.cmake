# LUMI
#
# module --force purge
# module load LUMI/25.03
# module load buildtools/25.03
# module load partition/G
# module load lumi-CPEtools
# module load PrgEnv-cray
# module load craype-x86-trento
# module load craype-accel-amd-gfx90a
# module load cray-libsci_acc
# module load rocm
# module load Boost
# module load cray-hdf5
# module load cray-netcdf
# module load Szip

# PrgEnv-cray provides cc/CC/ftn as generic wrappers that dispatch to
# whichever compiler the loaded PrgEnv-* module selects.
set(ENV{CC}  cc)
set(ENV{CXX} CC)
set(ENV{FC}  ftn)

set(RTE_USE_KMM ON)
set(RTE_USE_HIP ON)

set(CMAKE_HIP_ARCHITECTURES "gfx90a")
set(AMDGPU_TARGETS "gfx90a")
set(GPU_TARGETS "gfx90a")
set(USER_CXX_FLAGS "-std=c++17")
set(USER_CXX_FLAGS_RELEASE "-Ofast -DNDEBUG")
set(USER_CXX_FLAGS_DEBUG "-O2 -g -Wall -Wno-unknown-pragmas")
set(USER_HIP_FLAGS "-std=c++17")
set(USER_HIP_FLAGS_RELEASE "-Ofast")
set(USER_HIP_FLAGS_DEBUG "-O2 -g -Wall")

# src_kernels (Fortran) is always built, even for HIP/GPU targets. Cray
# Fortran's default REAL is 4 bytes; promote it to 8 to match the C++
# `Float` (double) type -- the equivalent of gfortran's
# "-fdefault-real-8 -fdefault-double-8" used by the other configs.
set(USER_FC_FLAGS "-s real64")
set(USER_FC_FLAGS_RELEASE "-O3")
set(USER_FC_FLAGS_DEBUG "-O0 -g")

set(NETCDF_LIB_C "netcdf")
set(HDF5_LIB "hdf5")
set(SZIP_LIB "sz")
set(LIBS ${NETCDF_LIB_C} ${HDF5_LIB} ${SZIP_LIB})
include_directories($ENV{NETCDF_DIR}/include)

# hipCUB/rocPRIM (the HIP/ROCm equivalent of CUB) are header-only and
# installed under the ROCm prefix provided by the "rocm" module, rather than
# a fixed location -- resolve it the same way external/kmm/CMakeLists.txt
# does, via the ROCM_PATH the module sets, falling back to /opt/rocm.
if(NOT DEFINED ENV{ROCM_PATH})
  set(ROCM_PATH "/opt/rocm")
else()
  set(ROCM_PATH $ENV{ROCM_PATH})
endif()
set(ROCM_INCLUDE_DIR "${ROCM_PATH}/include")
set(INCLUDE_DIRS ${ROCM_INCLUDE_DIR})

add_definitions(-DRTE_USE_CBOOL)
