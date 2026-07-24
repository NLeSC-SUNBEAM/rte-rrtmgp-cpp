# Ubuntu 20.04
if(RTE_USE_MPI) 
  set(ENV{CC}  mpicc ) # C compiler for parallel build
  set(ENV{CXX} mpicxx) # C++ compiler for parallel build
else()
  set(ENV{CC}  gcc) # C compiler for serial build
  set(ENV{CXX} g++) # C++ compiler for serial build
endif()

set(USER_CXX_FLAGS "-std=c++17")
set(USER_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -march=native")
set(USER_CXX_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")
set(USER_FC_FLAGS "-fdefault-real-8 -fdefault-double-8 -fPIC -ffixed-line-length-none -fno-range-check")
set(USER_FC_FLAGS_RELEASE "-DNDEBUG -O3 -march=native")
set(USER_FC_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")

set(CUB_INCLUDE_DIR "/usr/local/cuda/include")

# NetCDF/HDF5/Boost are located via find_package() in the top-level
# CMakeLists.txt; /usr is on CMake's default search path, no hint needed.
set(LIBS m z curl)
set(INCLUDE_DIRS ${CUB_INCLUDE_DIR})

if(RTE_USE_CUDA)
  set(CUDA_PROPAGATE_HOST_FLAGS OFF)
  set(CMAKE_CUDA_ARCHITECTURES 86)
  set(USER_CUDA_FLAGS "-std=c++17 -expt-relaxed-constexpr")
  set(USER_CUDA_FLAGS_RELEASE "-Xptxas -O3 -DNDEBUG")
  set(USER_CUDA_FLAGS_DEBUG "-Xptxas -O0 -g -G")
endif()

if(RTE_USE_HIP)
  # gfx90a (MI200-series) is just a reasonable default for compile-only CI
  # (no real GPU needed) -- adjust for whatever hardware this actually
  # targets.
  set(CMAKE_HIP_ARCHITECTURES gfx90a)
  set(USER_HIP_FLAGS "-std=c++17")
  set(USER_HIP_FLAGS_RELEASE "-O3 -DNDEBUG")
  set(USER_HIP_FLAGS_DEBUG "-O0 -g")

  # hipCUB/rocPRIM (the HIP/ROCm equivalent of CUB, see CUB_INCLUDE_DIR
  # above) are header-only and installed under the ROCm prefix rather than
  # a CUDA-toolkit-style location, so they need their own include path.
  set(ROCM_INCLUDE_DIR "/opt/rocm/include")
  list(APPEND INCLUDE_DIRS ${ROCM_INCLUDE_DIR})
endif()

add_definitions(-DRTE_USE_CBOOL)
