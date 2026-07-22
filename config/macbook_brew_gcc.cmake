# MacBook using GCC compiler from homebrew
if(RTE_USE_MPI) 
  set(ENV{CC}  mpicc ) # C compiler for parallel build
  set(ENV{CXX} mpicxx) # C++ compiler for parallel build
  set(ENV{FC}  mpif90) # Fortran compiler for parallel build
else()
  set(ENV{CC}  gcc-11)      # C compiler for serial build
  set(ENV{CXX} g++-11)      # C++ compiler for serial build
  set(ENV{FC}  gfortran-11) # Fortran compiler for parallel build
endif()

set(GNU_SED "gsed")

set(USER_CXX_FLAGS "-std=c++14")
set(USER_CXX_FLAGS_RELEASE "-DNDEBUG -O3 -march=native")
set(USER_CXX_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")
set(USER_FC_FLAGS "-std=f2003 -fdefault-real-8 -fdefault-double-8 -fPIC -ffixed-line-length-none -fno-range-check")
set(USER_FC_FLAGS_RELEASE "-DNDEBUG -O3 -march=native")
set(USER_FC_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")

# NetCDF/HDF5/Boost are located via find_package() in the top-level
# CMakeLists.txt. Homebrew's default prefix is /usr/local on Intel Macs and
# /opt/homebrew on Apple Silicon; hint both so find_package() works on either.
list(APPEND CMAKE_PREFIX_PATH "/usr/local" "/opt/homebrew")

set(LIBS m z curl)

add_definitions(-DRESTRICTKEYWORD=__restrict__)
add_definitions(-DRTE_USE_CBOOL)
