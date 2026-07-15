#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
FILE(GLOB sourcefiles_cuda_rt "../src_cuda_rt/*.cu")

add_library(rte_rrtmgp_cuda_rt STATIC ${sourcefiles_cuda_rt})
target_include_directories(rte_rrtmgp_cuda_rt SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp_cuda_rt
  PUBLIC  rte_rrtmgp_headers rte_rrtmgp_rt_headers
  PRIVATE rte_rrtmgp_kernels_cuda_rt)
