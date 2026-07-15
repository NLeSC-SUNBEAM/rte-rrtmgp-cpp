#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
# CTest wrapper around the existing rfmip_init.py / rfmip_run.py /
# compare-to-reference.py workflow documented in rfmip/README.md and used by
# ./check_rfmip.sh and .github/workflows/continuous-integration.yml. This
# does not replace either of those; it only gives the same three steps a
# `ctest` entry point. Data staging (make_links.sh, linking the
# test_rte_rrtmgp executable) is out of scope here and must still be done
# before running these tests, exactly as before.
#
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Matches the RRTMGP_ROOT / RRTMGP_DATA environment variables set in
# .github/workflows/continuous-integration.yml; compare-to-reference.py
# relies on RRTMGP_DATA being set.
set(rfmip_test_env
  "RRTMGP_ROOT=${CMAKE_SOURCE_DIR}"
  "RRTMGP_DATA=${CMAKE_SOURCE_DIR}/rrtmgp-data")

add_test(NAME rfmip_init
  COMMAND ${Python3_EXECUTABLE} rfmip_init.py
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

add_test(NAME rfmip_run
  COMMAND ${Python3_EXECUTABLE} rfmip_run.py
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

# Run through `sh -c` (rather than a plain COMMAND list) because --file takes
# a shell glob matching the per-case files rfmip_run.py just wrote, the same
# way check_rfmip.sh and the CI workflow invoke it. add_test()'s COMMAND does
# not go through a shell, so without this the pattern would be passed to the
# script unexpanded instead of matching the generated .nc files.
add_test(NAME rfmip_check
  COMMAND sh -c "${Python3_EXECUTABLE} compare-to-reference.py --ref_dir ../rrtmgp-data/examples/rfmip-clear-sky/reference --tst_dir . --var rld rlu rsd rsu --file r??_Efx_RTE-RRTMGP-181204_rad-irf_r1i1p1f1_gn.nc --failure_threshold=5.8e-2"
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

set_tests_properties(rfmip_init rfmip_run rfmip_check PROPERTIES ENVIRONMENT "${rfmip_test_env}")
set_tests_properties(rfmip_run   PROPERTIES DEPENDS rfmip_init)
set_tests_properties(rfmip_check PROPERTIES DEPENDS rfmip_run)
