#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
cmake_minimum_required (VERSION 3.18)

# Boost's own exported CMake config isn't guaranteed to exist on every
# machine this project builds on (e.g. EasyBuild-built Boost on das6 /
# snellius, built via b2 rather than CMake), so keep using CMake's bundled
# FindBoost.cmake module rather than requiring find_package(Boost) to find a
# Boost-provided config file. This is already the default behavior on
# CMake >= 3.30 when the policy is left unset, so it changes nothing; it
# just silences that version's CMP0167 dev warning ("The FindBoost module
# is removed") by making the choice explicit. Guarded because CMP0167 does
# not exist prior to CMake 3.30.
if(POLICY CMP0167)
  cmake_policy(SET CMP0167 OLD)
endif()

option(RTE_USE_CUDA "Build the CUDA (GPU) libraries and executables" OFF)
option(RTE_USE_HIP "Build the HIP (AMD GPU) libraries and executables" OFF)
option(RTE_USE_SP "Use single precision (32-bit) floats instead of double" OFF)
option(RTE_USE_MPI "Use MPI compiler wrappers (mpicc/mpicxx/mpif90)" OFF)
option(RTE_SAFE_RNG "Use a safer but slower pseudo-RNG initialization" OFF)
option(RTE_USE_KMM "Build against KMM (external/kmm) for GPU portability and multi-GPU support" OFF)

if(RTE_USE_CUDA AND RTE_USE_HIP)
  message(FATAL_ERROR "RTE_USE_CUDA and RTE_USE_HIP are mutually exclusive; enable only one.")
endif()

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_CURRENT_SOURCE_DIR}/config ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# Set the precision of the build.
if(RTE_USE_SP)
  message(STATUS "Precision: Single (32-bits) floats")
else()
  message(STATUS "Precision: Double (64-bits) floats")
endif()

# Load system specific settings if not set, force default.cmake.
if(NOT SYST)
  set(SYST default CACHE STRING
    "Name of the config file in config/ (without .cmake extension) providing compiler and library settings for this machine." FORCE)
endif()
include(${SYST} OPTIONAL RESULT_VARIABLE SYSTINC)

# Trigger fatal error if illegal module is loaded.
if(${SYSTINC} STREQUAL "NOTFOUND")
  message(FATAL_ERROR "Config file config/" ${SYST} ".cmake does not exist.")
endif()

# Set the default build type to RELEASE.
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING
    "Choose the type of build, options are: None Debug Release." FORCE)
else()
  string(TOUPPER ${CMAKE_BUILD_TYPE} TEMP)
  set(CMAKE_BUILD_TYPE ${TEMP} CACHE STRING
    "Choose the type of build, options are: None Debug Release." FORCE)
endif()

# Start the project only after the system specific settings are loaded.
# If CUDA is enabled, don't compile the Fortran kernels as they are not needed.
if(RTE_USE_CUDA)
  project(rte-rrtmgp-cpp C CXX Fortran CUDA)
else()
  project(rte-rrtmgp-cpp C CXX Fortran)
endif()

# Load the CUDA module in case CUDA is enabled and display status message.
if(RTE_USE_CUDA)
  message(STATUS "CUDA: Enabled.")
else()
  message(STATUS "CUDA: Disabled.")
endif()

if(RTE_USE_HIP)
  message(STATUS "HIP: Enabled.")
else()
  message(STATUS "HIP: Disabled.")
endif()

if (RTE_SAFE_RNG)
  message(STATUS "RTE_SAFE_RNG: Use safer but slower initialization of pseudo-rng.")
endif()

# Only set the compiler flags when the cache is created
# to enable editing of the flags in the CMakeCache.txt file.
if(NOT HASCACHE)
  set(CMAKE_C_FLAGS ${USER_C_FLAGS} CACHE STRING
    "Flags used by the C-compiler during all build types." FORCE)
  set(CMAKE_C_FLAGS_DEBUG ${USER_C_FLAGS_DEBUG} CACHE STRING
    "Flags used by the C-compiler during debug builds." FORCE)
  set(CMAKE_C_FLAGS_RELEASE ${USER_C_FLAGS_RELEASE} CACHE STRING
    "Flags used by the C-compiler during release builds." FORCE)

  set(CMAKE_CXX_FLAGS ${USER_CXX_FLAGS} CACHE STRING
    "Flags used by the CXX-compiler during all build types." FORCE)
  set(CMAKE_CXX_FLAGS_DEBUG ${USER_CXX_FLAGS_DEBUG} CACHE STRING
    "Flags used by the CXX-compiler during debug builds." FORCE)
  set(CMAKE_CXX_FLAGS_RELEASE ${USER_CXX_FLAGS_RELEASE} CACHE STRING
    "Flags used by the CXX-compiler during release builds." FORCE)

  set(CMAKE_Fortran_FLAGS ${USER_FC_FLAGS} CACHE STRING
    "Flags used by the Fortran-compiler during all build types." FORCE)
  set(CMAKE_Fortran_FLAGS_DEBUG ${USER_FC_FLAGS_DEBUG} CACHE STRING
    "Flags used by the Fortran-compiler during debug builds." FORCE)
  set(CMAKE_Fortran_FLAGS_RELEASE ${USER_FC_FLAGS_RELEASE} CACHE STRING
    "Flags used by the Fortran-compiler during release builds." FORCE)

  if(RTE_USE_CUDA)
    set(CMAKE_CUDA_FLAGS ${USER_CUDA_FLAGS} CACHE STRING
      "Flags used by the CXX-compiler during all build types." FORCE)
    set(CMAKE_CUDA_FLAGS_DEBUG ${USER_CUDA_FLAGS_DEBUG} CACHE STRING
      "Flags used by the CXX-compiler during debug builds." FORCE)
    set(CMAKE_CUDA_FLAGS_RELEASE ${USER_CUDA_FLAGS_RELEASE} CACHE STRING
      "Flags used by the CXX-compiler during release builds." FORCE)
  endif()

  message(STATUS "Build Type: " ${CMAKE_BUILD_TYPE})
  set(HASCACHE TRUE CACHE BOOL "CMakeCache.txt created." FORCE)

  # Make sure that ccmake only contains build type.
  mark_as_advanced(HASCACHE)
  mark_as_advanced(CMAKE_INSTALL_PREFIX)
endif()

# Print the C++ and CUDA compiler flags to the screen.
if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
  message(STATUS "CXX-compiler flags: " ${CMAKE_CXX_FLAGS} " " ${CMAKE_CXX_FLAGS_RELEASE})
  message(STATUS "Fortran-compiler flags: " ${CMAKE_CXX_FLAGS} " " ${CMAKE_CXX_FLAGS_RELEASE})
else()
  message(STATUS "CXX-compiler flags: " ${CMAKE_CXX_FLAGS} " " ${CMAKE_CXX_FLAGS_DEBUG})
  message(STATUS "Fortran-compiler flags: " ${CMAKE_CXX_FLAGS} " " ${CMAKE_CXX_FLAGS_DEBUG})
endif()
if(RTE_USE_CUDA)
  if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
    message(STATUS "NVCC-compiler flags: " ${CMAKE_CUDA_FLAGS} " " ${CMAKE_CUDA_FLAGS_RELEASE})
  else()
    message(STATUS "NVCC-compiler flags: " ${CMAKE_CUDA_FLAGS} " " ${CMAKE_CUDA_FLAGS_DEBUG})
  endif()
endif()

# Third-party dependencies for configs that have been migrated off hardcoded
# library paths (see the comments at the top of the migrated config/*.cmake
# files). annuna/cloudy/das5 still set NETCDF_LIB_C themselves and keep
# working through the legacy ${LIBS}/${INCLUDE_DIRS} variables further down
# this file -- this block, and the target_link_libraries(... NetCDF::NetCDF
# ...) calls it enables, are skipped entirely for those three and have no
# effect on them.
if(NOT NETCDF_LIB_C)
  find_package(NetCDF REQUIRED)
  find_package(HDF5 REQUIRED COMPONENTS C)
  find_package(Boost REQUIRED)
endif()

# KMM (https://github.com/NLeSC/kmm) provides GPU portability (CUDA/HIP) and
# multi-GPU support. Vendored as the "external/kmm" submodule. Off by default
# since it pulls in its own fmt/spdlog submodule dependencies and is not yet
# used by any target; its CUDA/HIP backend follows RTE_USE_CUDA/RTE_USE_HIP
# (which are themselves mutually exclusive, checked above).
if(RTE_USE_KMM)
  message(STATUS "KMM: Enabled.")
  set(KMM_USE_CUDA ${RTE_USE_CUDA} CACHE BOOL "Build the KMM CUDA backend" FORCE)
  set(KMM_USE_HIP ${RTE_USE_HIP} CACHE BOOL "Build the KMM HIP backend" FORCE)
  add_subdirectory(external/kmm)
else()
  message(STATUS "KMM: Disabled.")
endif()

# Shared INTERFACE "libraries" that carry include directories and compile
# definitions to every target via target_link_libraries(), replacing the
# directory-scoped include_directories()/add_definitions() calls that used
# to apply blindly to every target in every subdirectory.
add_library(rte_rrtmgp_headers INTERFACE)
target_include_directories(rte_rrtmgp_headers INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
if(RTE_USE_CUDA)
  target_compile_definitions(rte_rrtmgp_headers INTERFACE RTE_USE_CUDA)
endif()
if(RTE_USE_SP)
  target_compile_definitions(rte_rrtmgp_headers INTERFACE RTE_USE_SP)
endif()

if(RTE_USE_CUDA)
  add_library(rte_rrtmgp_cuda_headers INTERFACE)
  target_include_directories(rte_rrtmgp_cuda_headers INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include/gpu")

  add_library(rte_rrtmgp_rt_headers INTERFACE)
  target_include_directories(rte_rrtmgp_rt_headers INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include_rt" "${CMAKE_CURRENT_SOURCE_DIR}/include_rt_kernels"
    # tools_gpu.h / tuner.h in include/gpu are shared CUDA infrastructure,
    # not two-stream-specific -- src_kernels_cuda_rt/src_cuda_rt use them
    # directly (bare #include) without linking rte_rrtmgp_cuda_headers.
    "${CMAKE_CURRENT_SOURCE_DIR}/include/gpu")
  if(RTE_SAFE_RNG)
    target_compile_definitions(rte_rrtmgp_rt_headers INTERFACE RTE_SAFE_RNG)
  endif()

  add_subdirectory(src_kernels_cuda)
  add_subdirectory(src_cuda)
  add_subdirectory(src_kernels_cuda_rt)
  add_subdirectory(src_cuda_rt)
endif()

add_subdirectory(src)
add_subdirectory(src_kernels)
add_subdirectory(src_test)

# ctest entry point for the existing rfmip/allsky Python-script test cases.
# Data staging (make_links.sh, linking the test_rte_rrtmgp executable) is
# not handled here, same as it wasn't handled by the shell scripts or the
# CI workflow this replaces -- run it before `ctest` as documented in each
# test directory's README.
enable_testing()
add_subdirectory(rfmip)
add_subdirectory(allsky)
