FILE(GLOB sourcefiles_rt CONFIGURE_DEPENDS
    "../src_kernels_cuda_rt/gas_optics_rrtmgp_kernels_launchers_rt.cu"
    "../src_kernels_cuda_rt/optical_props_kernels_launchers_rt.cu"
    "../src_kernels_cuda_rt/rte_solver_kernels_launchers_rt.cu"
    "../src_kernels_cuda_rt/subset_kernels_launchers_rt.cu"
    "../src_kernels_cuda_rt/gpt_combine_kernels_launchers_rt.cu"
    "../src_kernels_cuda_rt/raytracer_kernels_sw.cu"
    "../src_kernels_cuda_rt/raytracer_kernels_lw.cu"
    "../src_kernels_cuda_rt/raytracer_kernels_bw.cu")


if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
    set_source_files_properties("../src_kernels_cuda_rt/raytracer_kernels_sw.cu" PROPERTIES COMPILE_FLAGS --use_fast_math)
    set_source_files_properties("../src_kernels_cuda_rt/raytracer_kernels_lw.cu" PROPERTIES COMPILE_FLAGS --use_fast_math)
    set_source_files_properties("../src_kernels_cuda_rt/raytracer_kernels_bw.cu" PROPERTIES COMPILE_FLAGS --use_fast_math)
endif()

# See src_cuda/CMakeLists.txt for why this is needed under RTE_USE_HIP.
if(RTE_USE_HIP)
  set_source_files_properties(${sourcefiles_rt} PROPERTIES LANGUAGE HIP)
endif()

add_library(rte_rrtmgp_kernels_cuda_rt STATIC ${sourcefiles_rt})
target_include_directories(rte_rrtmgp_kernels_cuda_rt SYSTEM PRIVATE ${INCLUDE_DIRS})
target_link_libraries(rte_rrtmgp_kernels_cuda_rt PRIVATE rte_rrtmgp_headers rte_rrtmgp_rt_headers)
if(RTE_USE_KMM)
  target_link_libraries(rte_rrtmgp_kernels_cuda_rt PRIVATE kmm)
endif()


