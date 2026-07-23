#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
FILE(GLOB sourcefiles_cuda_rt CONFIGURE_DEPENDS "../src_cuda_rt/*.cu")

# See src_cuda/CMakeLists.txt for why this is needed under RTE_USE_HIP.
if(RTE_USE_HIP)
  set_source_files_properties(${sourcefiles_cuda_rt} PROPERTIES LANGUAGE HIP)
endif()

add_library(rte_rrtmgp_cuda_rt STATIC ${sourcefiles_cuda_rt})
target_include_directories(rte_rrtmgp_cuda_rt SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp_cuda_rt
  PUBLIC  rte_rrtmgp_headers rte_rrtmgp_rt_headers
  PRIVATE rte_rrtmgp_kernels_cuda_rt)
if(TARGET Boost::boost)
  target_link_libraries(rte_rrtmgp_cuda_rt PRIVATE Boost::boost)
endif()
if(RTE_USE_KMM)
  target_link_libraries(rte_rrtmgp_cuda_rt PUBLIC kmm)
endif()
