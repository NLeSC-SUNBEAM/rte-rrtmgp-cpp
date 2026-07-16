#[=======================================================================[
FindNetCDF
----------

Finds the NetCDF-C library and headers.

CMake does not bundle a NetCDF find module, and not every NetCDF-C install
ships its own CMake config file (notably Debian/Ubuntu's libnetcdf-dev does
not), so this project vendors a small MODULE-mode find module instead of
relying on `find_package(NetCDF CONFIG)`.

Searches standard system locations plus CMAKE_PREFIX_PATH / NetCDF_ROOT (or
the NETCDF_ROOT environment variable), matching CMake's usual find_package()
hint conventions -- see config/das6.cmake / config/snellius.cmake for how
per-machine hints are supplied.

Result variables:
  NetCDF_FOUND         - true if the header and library were both found
  NetCDF_INCLUDE_DIRS  - directory containing netcdf.h
  NetCDF_LIBRARIES     - full path to the NetCDF-C library

Imported target:
  NetCDF::NetCDF       - usage-requirement target carrying the include
                          directory and link library above
#]=======================================================================]

find_path(NetCDF_INCLUDE_DIR
  NAMES netcdf.h
  HINTS ${NetCDF_ROOT} ENV NETCDF_ROOT
  PATH_SUFFIXES include)

find_library(NetCDF_LIBRARY
  NAMES netcdf
  HINTS ${NetCDF_ROOT} ENV NETCDF_ROOT
  PATH_SUFFIXES lib lib64)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(NetCDF
  REQUIRED_VARS NetCDF_LIBRARY NetCDF_INCLUDE_DIR)

if(NetCDF_FOUND AND NOT TARGET NetCDF::NetCDF)
  add_library(NetCDF::NetCDF UNKNOWN IMPORTED)
  set_target_properties(NetCDF::NetCDF PROPERTIES
    IMPORTED_LOCATION "${NetCDF_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${NetCDF_INCLUDE_DIR}")
endif()

mark_as_advanced(NetCDF_INCLUDE_DIR NetCDF_LIBRARY)

set(NetCDF_INCLUDE_DIRS ${NetCDF_INCLUDE_DIR})
set(NetCDF_LIBRARIES ${NetCDF_LIBRARY})
