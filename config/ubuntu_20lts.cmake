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

# NetCDF/HDF5/Boost are located via find_package() in the top-level
# CMakeLists.txt; /usr is on CMake's default search path, no hint needed.
set(LIBS m z curl)

if(RTE_USE_CUDA)
  set(CUDA_PROPAGATE_HOST_FLAGS OFF)
  set(CMAKE_CUDA_ARCHITECTURES 80)
  set(USER_CUDA_FLAGS "-std=c++17 -expt-relaxed-constexpr")
  set(USER_CUDA_FLAGS_RELEASE "-Xptxas -O3 -DNDEBUG")
  set(USER_CUDA_FLAGS_DEBUG "-Xptxas -O0 -g -G")
endif()

add_definitions(-DRTE_USE_CBOOL)
