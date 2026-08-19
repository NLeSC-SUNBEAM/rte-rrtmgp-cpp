#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
# retrieve the git hash from the current commit
find_package(Git)

if(GIT_EXECUTABLE)
  execute_process(
    COMMAND git describe --dirty
    OUTPUT_STRIP_TRAILING_WHITESPACE
    OUTPUT_VARIABLE GITHASH
    RESULT_VARIABLE GITRETURN)
  if(NOT GITRETURN MATCHES 0)
    set(GITHASH "not available")
  endif()
else()
  set(GITHASH "not available")
endif()

message(STATUS "Git hash " ${GITHASH})

# NetCDF/HDF5/Boost picked up via find_package() in the top-level
# CMakeLists.txt, for configs that have been migrated off hardcoded library
# paths. Empty (and therefore a no-op below) for configs that haven't --
# those still get netcdf/hdf5 through the legacy ${LIBS} variable.
set(rte_rrtmgp_find_pkg_libs "")
if(TARGET NetCDF::NetCDF)
  list(APPEND rte_rrtmgp_find_pkg_libs NetCDF::NetCDF)
endif()
if(HDF5_FOUND)
  list(APPEND rte_rrtmgp_find_pkg_libs ${HDF5_LIBRARIES})
endif()
if(TARGET Boost::boost)
  list(APPEND rte_rrtmgp_find_pkg_libs Boost::boost)
endif()

if(RTE_USE_CUDA OR RTE_USE_HIP)
  if(RTE_USE_HIP)
    set_source_files_properties(
      radiation_solver.cu test_rte_rrtmgp.cu
      radiation_solver_rt.cu test_rte_rrtmgp_rt.cu radiation_solver_bw.cu
      test_rt_lite.cu
      PROPERTIES LANGUAGE HIP)
    # Mixing HIP-language sources into test_rte_rrtmgp_rt alongside this
    # plain C++ file makes CMake's HIP-language support misidentify its
    # language too (LINKER_LANGUAGE resolves to HIP for the whole target,
    # which drags this source along) -- pin it back to CXX explicitly.
    set_source_files_properties(../src_tilt/tilt_utils.cpp PROPERTIES LANGUAGE CXX)
    set(rand_lib hiprand)
  else()
    set(rand_lib curand)
  endif()

  add_executable(test_rte_rrtmgp radiation_solver.cu test_rte_rrtmgp.cu)
  target_include_directories(test_rte_rrtmgp PRIVATE "../include_test")
  target_include_directories(test_rte_rrtmgp SYSTEM PRIVATE ${INCLUDE_DIRS})
  target_compile_definitions(test_rte_rrtmgp PRIVATE GITHASH="${GITHASH}")
  target_link_libraries(test_rte_rrtmgp PRIVATE rte_rrtmgp rte_rrtmgp_cuda ${LIBS} ${rte_rrtmgp_find_pkg_libs} m)

  add_executable(test_rte_rrtmgp_rt radiation_solver_rt.cu test_rte_rrtmgp_rt.cu radiation_solver_bw.cu ../src_tilt/tilt_utils.cpp)
  target_include_directories(test_rte_rrtmgp_rt PRIVATE "../include_test" "../include_tilt")
  target_include_directories(test_rte_rrtmgp_rt SYSTEM PRIVATE ${INCLUDE_DIRS})
  target_compile_definitions(test_rte_rrtmgp_rt PRIVATE GITHASH="${GITHASH}")
  target_link_libraries(test_rte_rrtmgp_rt PRIVATE rte_rrtmgp rte_rrtmgp_cuda rte_rrtmgp_cuda_rt ${rand_lib} ${LIBS} ${rte_rrtmgp_find_pkg_libs} m)

  #add_executable(test_rte_rrtmgp_bw radiation_solver_bw.cu test_rte_rrtmgp_bw.cu)
  #target_link_libraries(test_rte_rrtmgp_bw PRIVATE rte_rrtmgp rte_rrtmgp_cuda rte_rrtmgp_cuda_rt curand ${LIBS} m)

  add_executable(test_rt_lite test_rt_lite.cu)
  target_include_directories(test_rt_lite PRIVATE "../include_test")
  target_include_directories(test_rt_lite SYSTEM PRIVATE ${INCLUDE_DIRS})
  target_compile_definitions(test_rt_lite PRIVATE GITHASH="${GITHASH}")
  target_link_libraries(test_rt_lite PRIVATE rte_rrtmgp_cuda rte_rrtmgp_cuda_rt ${rand_lib} ${LIBS} ${rte_rrtmgp_find_pkg_libs} m)
else()
  add_executable(test_rte_rrtmgp radiation_solver.cpp test_rte_rrtmgp.cpp)
  target_include_directories(test_rte_rrtmgp PRIVATE "../include_test")
  target_include_directories(test_rte_rrtmgp SYSTEM PRIVATE ${INCLUDE_DIRS})
  target_compile_definitions(test_rte_rrtmgp PRIVATE GITHASH="${GITHASH}")
  target_link_libraries(test_rte_rrtmgp PRIVATE rte_rrtmgp ${LIBS} ${rte_rrtmgp_find_pkg_libs} m)
endif()
