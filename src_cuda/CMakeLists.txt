#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
FILE(GLOB sourcefiles_cuda "../src_cuda/*.cu")

add_library(rte_rrtmgp_cuda STATIC ${sourcefiles_cuda})
target_include_directories(rte_rrtmgp_cuda SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp_cuda
  PUBLIC  rte_rrtmgp_headers rte_rrtmgp_cuda_headers
  PRIVATE rte_rrtmgp_kernels_cuda)
