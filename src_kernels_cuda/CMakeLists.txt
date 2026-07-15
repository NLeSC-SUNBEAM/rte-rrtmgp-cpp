FILE(GLOB sourcefiles
    "../src_kernels_cuda/gas_optics_rrtmgp_kernels_launchers.cu"
    "../src_kernels_cuda/optical_props_kernels_launchers.cu"
    "../src_kernels_cuda/rte_solver_kernels_launchers.cu"
    "../src_kernels_cuda/subset_kernels_launchers.cu"
    "../src_kernels_cuda/fluxes_kernels_launchers.cu")

add_library(rte_rrtmgp_kernels_cuda STATIC ${sourcefiles})
target_include_directories(rte_rrtmgp_kernels_cuda SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp_kernels_cuda PRIVATE rte_rrtmgp_headers rte_rrtmgp_cuda_headers)
