#
# This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
#
# CTest wrapper around the existing allsky_init.py / allsky_run.py /
# allsky_check.py workflow documented in allsky/README.md and used by
# ./check_allsky.sh. This does not replace either of those; it only gives the
# same three steps a `ctest` entry point. Data staging (make_links.sh,
# linking the test_rte_rrtmgp executable) is out of scope here and must
# still be done before running these tests, exactly as before.
#
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Matches the RRTMGP_ROOT / RRTMGP_DATA environment variables set in
# .github/workflows/continuous-integration.yml; allsky_check.py's --ref_dir
# default reads os.environ["RRTMGP_DATA"] unconditionally at argument-parser
# construction time, so this must be set even when --ref_dir isn't given
# explicitly.
set(allsky_test_env
  "RRTMGP_ROOT=${CMAKE_SOURCE_DIR}"
  "RRTMGP_DATA=${CMAKE_SOURCE_DIR}/rrtmgp-data")

add_test(NAME allsky_init
  COMMAND ${Python3_EXECUTABLE} allsky_init.py
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

add_test(NAME allsky_run
  COMMAND ${Python3_EXECUTABLE} allsky_run.py
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

# CI (.github/workflows/continuous-integration.yml) overrides the script's
# own default failure_threshold (1.e-5) to 5.8e-2, matching rfmip; mirrored
# here so ctest agrees with the currently-trusted pass criterion.
add_test(NAME allsky_check
  COMMAND ${Python3_EXECUTABLE} allsky_check.py --failure_threshold=5.8e-2
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

set_tests_properties(allsky_init allsky_run allsky_check PROPERTIES ENVIRONMENT "${allsky_test_env}")
set_tests_properties(allsky_run   PROPERTIES DEPENDS allsky_init)
set_tests_properties(allsky_check PROPERTIES DEPENDS allsky_run)
