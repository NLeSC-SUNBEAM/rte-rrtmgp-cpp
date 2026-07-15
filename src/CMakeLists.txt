#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
FILE(GLOB sourcefiles "../src/*.cpp")

add_library(rte_rrtmgp STATIC ${sourcefiles} aerosol_optics.cpp ../include/aerosol_optics.h)
target_include_directories(rte_rrtmgp SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp
  PUBLIC  rte_rrtmgp_headers
  PRIVATE rte_rrtmgp_kernels)
