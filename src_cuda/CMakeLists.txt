#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
FILE(GLOB sourcefiles_cuda CONFIGURE_DEPENDS "../src_cuda/*.cu")

# CMake only auto-detects CUDA vs HIP by file extension (.cu vs .hip); these
# sources stay .cu for both backends (RTE_USE_CUDA/RTE_USE_HIP are mutually
# exclusive, so only one of the two ever actually compiles them), so under
# HIP they need to be told explicitly which language to use, matching the
# same pattern external/kmm/CMakeLists.txt uses for its own sources.
if(RTE_USE_HIP)
  set_source_files_properties(${sourcefiles_cuda} PROPERTIES LANGUAGE HIP)
endif()

add_library(rte_rrtmgp_cuda STATIC ${sourcefiles_cuda})
target_include_directories(rte_rrtmgp_cuda SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp_cuda
  PUBLIC  rte_rrtmgp_headers rte_rrtmgp_cuda_headers
  PRIVATE rte_rrtmgp_kernels_cuda)
if(TARGET Boost::boost)
  target_link_libraries(rte_rrtmgp_cuda PRIVATE Boost::boost)
endif()
if(RTE_USE_KMM)
  target_link_libraries(rte_rrtmgp_cuda PUBLIC kmm)
endif()
