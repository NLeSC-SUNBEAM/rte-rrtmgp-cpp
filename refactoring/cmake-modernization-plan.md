# CMake modernization plan

Status: proposed, not started.

Scope: the CMake build system only (`CMakeLists.txt` at the repo root and in
`src/`, `src_cuda/`, `src_cuda_rt/`, `src_kernels/`, `src_kernels_cuda/`,
`src_kernels_cuda_rt/`, `src_test/`, plus the per-machine `config/*.cmake`
files). This is **orthogonal** to
[`cpu-gpu-deduplication-plan.md`](cpu-gpu-deduplication-plan.md) — it does not
move, rename, or merge any C++/CUDA/Fortran source file, and does not change
which `.cpp`/`.cu` files exist. The two efforts can land independently and in
either order. No source in `src_cuda_rt/`, `include_rt/`,
`src_kernels_cuda_rt/`, `include_rt_kernels/` needs to change either, though
its `CMakeLists.txt` does get the same generic treatment as everything else
(target-based include dirs, explicit source lists) since that's pure build
plumbing, not "the ray tracer".

## 1. Problem recap

Inventory of what exists today:

| File | Role |
|---|---|
| `CMakeLists.txt` | top-level: precision, config include, project(), flags, subdirectory wiring |
| `src/CMakeLists.txt` | CPU physics library `rte_rrtmgp` |
| `src_cuda/CMakeLists.txt` | GPU physics library `rte_rrtmgp_cuda` |
| `src_cuda_rt/CMakeLists.txt` | GPU ray-tracer library `rte_rrtmgp_cuda_rt` |
| `src_kernels/CMakeLists.txt` | Fortran kernel library `rte_rrtmgp_kernels` |
| `src_kernels_cuda/CMakeLists.txt` | CUDA kernel-launcher library `rte_rrtmgp_kernels_cuda` |
| `src_kernels_cuda_rt/CMakeLists.txt` | CUDA ray-tracer kernel library `rte_rrtmgp_kernels_cuda_rt` |
| `src_test/CMakeLists.txt` | test executables (`test_rte_rrtmgp`, `test_rte_rrtmgp_rt`, `test_rt_lite`) |
| `config/*.cmake` (8 files: `macbook_brew`, `macbook_brew_gcc`, `ubuntu`, `ubuntu_20lts`, `ubuntu_22lts`, `annuna`, `cloudy`, `das5`, `das6`, `snellius`) | per-machine compiler/library selection, `include()`-ed by `-DSYST=<name>` |

Concrete issues found, with locations:

1. **Toggles aren't declared options.** `USECUDA`, `USESP`, `USEMPI`,
   `SAFERNG` are bare, undeclared variables checked with `if()`
   (`CMakeLists.txt:9,39,46,53`). They don't show up in `cmake -LH` or
   `ccmake`, have no help text, no type, and no validation — `-DUSECUDA=1`
   silently does nothing (CMake wants `ON`/`TRUE`/`1` to be truthy, but
   there's no error path for typos like `-DUSECUDA=yes` vs `-DUSE_CUDA=ON`).

2. **No `find_package`, all library paths hand-written per machine.** Every
   `config/*.cmake` hardcodes absolute paths, e.g.
   `config/macbook_brew.cmake`: `set(NETCDF_LIB_C "/usr/local/lib/libnetcdf.dylib")`,
   `config/ubuntu_22lts.cmake`: `"/usr/lib/x86_64-linux-gnu/libnetcdf.so"`,
   `config/das6.cmake`: `"/opt/ohpc/pub/libs/gnu9/openmpi4/netcdf/4.7.3/lib/libnetcdf.so"`.
   This is a per-machine `Makefile.inc` translated line-for-line into CMake
   syntax — every new machine needs a brand-new file with hand-discovered
   paths, and there is no error if a path is wrong until link time.

3. **Global directory-scoped state instead of targets.**
   `include_directories()` and `add_definitions()` are used everywhere
   (`src/CMakeLists.txt:5`, `src_cuda/CMakeLists.txt:5`,
   `src_cuda_rt/CMakeLists.txt:5`, `src_kernels_cuda/CMakeLists.txt:8`,
   `src_test/CMakeLists.txt:4`) instead of `target_include_directories()` /
   `target_compile_definitions()`. `target_link_libraries()` calls
   (`src/CMakeLists.txt:8`, `src_cuda/CMakeLists.txt:8`,
   `src_test/CMakeLists.txt:29,32,38,41`) never use
   `PUBLIC`/`PRIVATE`/`INTERFACE`, so CMake falls back to old-style linking
   with no propagation control. Consequence: the same include-dir list
   (`"../include" "../include_kernels_cuda"` etc.) is copy-pasted across 5+
   files and has to be kept in sync by hand whenever a new shared header
   directory is added.

4. **`FILE(GLOB ...)` for every source list**
   (`src/CMakeLists.txt:4`, `src_cuda/CMakeLists.txt:4`,
   `src_cuda_rt/CMakeLists.txt:4`, `src_kernels/CMakeLists.txt:4`,
   `src_kernels_cuda/CMakeLists.txt:1`,
   `src_kernels_cuda_rt/CMakeLists.txt:1`). This is CMake's most
   well-documented anti-pattern: adding or removing a `.cpp`/`.cu` file
   doesn't invalidate the generated build system, so a stale build can
   silently omit a new file until someone reruns `cmake` by hand.

5. **Compiler selection via `set(ENV{CXX} ...)` inside config files**
   (every `config/*.cmake`), read before `project()` is called
   (`CMakeLists.txt:20` happens before `CMakeLists.txt:40/42`). This
   pattern exists because CMake won't let you change
   `CMAKE_CXX_COMPILER` after `project()` — but it's a workaround for not
   using the standard mechanism (`-DCMAKE_CXX_COMPILER=...` or a proper
   `CMAKE_TOOLCHAIN_FILE`), and it's invisible to anyone inspecting the
   CMake cache.

6. **Hand-rolled cache-flag guard.** `CMakeLists.txt:58-97` sets
   `CMAKE_CXX_FLAGS`, `CMAKE_CXX_FLAGS_RELEASE`, `CMAKE_CXX_FLAGS_DEBUG`,
   and the Fortran/CUDA equivalents as `CACHE ... FORCE`, gated by a
   custom `HASCACHE` bookkeeping variable so it only runs once. This
   exists to let users hand-edit `CMakeCache.txt` afterwards without being
   overwritten on the next `cmake` run — a real concern, but the standard
   solution is simply *not* forcing these on every configure, or using
   `target_compile_options()` per target so `ccmake`/cache editing works
   the normal way.

7. **`curand` linked as a bare library name**
   (`src_test/CMakeLists.txt:32,38`), relying on it being found on the
   linker's default search path rather than via
   `find_package(CUDAToolkit)` → `CUDA::curand`, which resolves correctly
   regardless of CUDA install location.

8. **Stale `FindCUDA`-module variables mixed with native CUDA-language
   flags.** `config/das6.cmake` sets `CUDA_PROPAGATE_HOST_FLAGS` and
   appends to `CUDA_NVCC_FLAGS` — those are `FindCUDA.cmake` module
   variables (deprecated since CMake 3.10). This project uses CUDA as a
   native `project()` language (`CMakeLists.txt:40`) and actually reads
   `USER_CUDA_FLAGS`/`CMAKE_CUDA_FLAGS`
   (`CMakeLists.txt:83-89`) — so on `das6`, anything appended to
   `CUDA_NVCC_FLAGS` is silently ignored. This is a live bug, not just a
   style issue, and would be quietly fixed by consolidating on one
   mechanism.

9. **No CTest integration.** `rfmip`/`allsky`/`rcemip` are run via
   standalone Python scripts (see README and
   `.github/workflows/continuous-integration.yml:36-52`), invoked
   manually or duplicated in CI as raw shell steps. There's no single
   `ctest` entry point, so local validation and CI validation are two
   independently-maintained scripts.

10. **CI only ever exercises one configuration**
    (`.github/workflows/continuous-integration.yml`: `cmake -DSYST=ubuntu_22lts ..`,
    no `USECUDA`, no `USESP`). This isn't a CMake-file bug per se, but it
    means most of the option-combinations described above are currently
    untested by CI — worth strengthening as part of this work (see §6).

## 2. Goals

- Replace ad-hoc variables with declared `option()`s that show up in
  `cmake -LH` / `ccmake` with real help text and types.
- Replace hardcoded per-machine library paths with `find_package()` calls,
  with per-machine `config/*.cmake` files reduced to compiler selection,
  optimization flags, and *hints* (e.g. `CMAKE_PREFIX_PATH`,
  `NetCDF_ROOT`) rather than full absolute paths — without breaking builds
  on clusters that install dependencies to non-standard prefixes.
- Move every directory-scoped `include_directories()`/`add_definitions()`
  call to target-scoped `target_include_directories()` /
  `target_compile_definitions()` with correct `PUBLIC`/`PRIVATE` visibility,
  eliminating the copy-pasted include-dir lists.
- Replace `FILE(GLOB ...)` with explicit source lists (or, if the team
  prefers to keep glob's convenience, `FILE(GLOB ... CONFIGURE_DEPENDS)` as
  the minimum fix — see §3.4 for the tradeoff).
- Add `enable_testing()` + `add_test()` wrappers around the existing
  rfmip/allsky/rcemip Python scripts so `ctest` becomes a single validation
  entry point, reusable by both local developers and CI.
- Do all of this without changing: which executables get built, their
  names, the `-DSYST=`/`-DUSECUDA=`/`-DUSESP=` command-line invocation
  developers already type (per README), or numerical output.

## 3. Target architecture

### 3.1 Declared options in the top-level `CMakeLists.txt`

Replace the bare-variable checks with:

```cmake
option(USECUDA "Build the CUDA (GPU) libraries and executables" OFF)
option(USESP   "Use single precision (32-bit) floats instead of double" OFF)
option(USEMPI  "Use MPI compiler wrappers (mpicc/mpicxx/mpif90)" OFF)
option(SAFERNG "Use a safer but slower pseudo-RNG initialization" OFF)
```

placed right after `cmake_minimum_required()`, before `config/${SYST}.cmake`
is included (config files may still read these to branch on `USECUDA`, same
as today — only the declaration mechanism changes, not the read side).
`option()` variables are booleans by construction, so `-DUSECUDA=ON` /
`-DUSECUDA=1` / `-DUSECUDA=TRUE` all work and `-DUSECUDA=nonsense` throws a
normal CMake type error instead of silently being falsy.

`SYST` itself stays a plain cached string (`set(SYST default CACHE STRING ...)`
if unset) since it's not boolean — but give it a proper `CACHE STRING` entry
with a docstring instead of the current bare `set(SYST default)` at
`CMakeLists.txt:18`, so it's visible in `cmake -LH`.

### 3.2 `config/*.cmake` → compiler + flags + hints, not hardcoded paths

Today's `config/ubuntu_22lts.cmake` hardcodes:

```cmake
set(NETCDF_INCLUDE_DIR "/usr/include")
set(NETCDF_LIB_C       "/usr/lib/x86_64-linux-gnu/libnetcdf.so")
set(HDF5_LIB_1         "/usr/lib/x86_64-linux-gnu/libhdf5_serial.so")
set(HDF5_LIB_2         "/usr/lib/x86_64-linux-gnu/libhdf5_serial_hl.so")
```

Target version — the config file only sets *search hints*, and the actual
resolution happens once, centrally, via `find_package`:

```cmake
# config/ubuntu_22lts.cmake
if(USEMPI)
  set(ENV{CC} mpicc); set(ENV{CXX} mpicxx); set(ENV{FC} mpif90)
else()
  set(ENV{CC} gcc); set(ENV{CXX} g++); set(ENV{FC} gfortran)
endif()

set(USER_CXX_FLAGS "-std=c++17")
set(USER_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -march=native")
set(USER_CXX_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")
set(USER_FC_FLAGS "-fdefault-real-8 -fdefault-double-8 -fPIC -ffixed-line-length-none -fno-range-check")
set(USER_FC_FLAGS_RELEASE "-DNDEBUG -O3 -march=native")
set(USER_FC_FLAGS_DEBUG "-O0 -g -Wall -Wno-unknown-pragmas")

if(USECUDA)
  set(CMAKE_CUDA_ARCHITECTURES 86)
  set(USER_CUDA_FLAGS "-std=c++17 -expt-relaxed-constexpr")
  set(USER_CUDA_FLAGS_RELEASE "-Xptxas -O3 -DNDEBUG")
  set(USER_CUDA_FLAGS_DEBUG "-Xptxas -O0 -g -G -DCUDACHECKS")
  set(RTE_RRTMGP_GPU_MEMPOOL "CUDA")   # see 3.3 for how this becomes a target define
endif()

set(RESTRICTKEYWORD "__restrict__")
```

No `NETCDF_LIB_C`, no `HDF5_LIB_1`, no absolute paths at all — those become
the job of `find_package(NetCDF)` / `find_package(HDF5)` in the top-level
`CMakeLists.txt`, run once, using standard `CMAKE_PREFIX_PATH` /
`<Package>_ROOT` hints. For machines with non-standard install layouts
(`das6`, `snellius`, `annuna`, `cloudy`), the file keeps a hint instead of a
full path:

```cmake
# config/das6.cmake
list(APPEND CMAKE_PREFIX_PATH "/opt/ohpc/pub/libs/gnu9/openmpi4/netcdf/4.7.3")
list(APPEND CMAKE_PREFIX_PATH "/opt/ohpc/pub/libs/gnu9/openmpi4/hdf5/1.10.6")
list(APPEND CMAKE_PREFIX_PATH "/opt/ohpc/pub/libs/gnu9/openmpi4/boost/1.73.0")
```

`find_package(NetCDF)` will then search those prefixes plus the standard
system ones. This preserves cluster support (nothing forces every machine
onto a "standard" prefix) while removing the maintenance burden of
hand-listing every `.so` file — a NetCDF upgrade on a cluster becomes a
one-line version-in-path change instead of editing 3+ `set(..._LIB ...)`
lines.

**Caveat to flag explicitly**: CMake does not ship a built-in
`FindNetCDF.cmake` module. Recent NetCDF-C builds (≥ 4.7 built with CMake)
export a `netCDFConfig.cmake` that `find_package(netCDF CONFIG)` picks up
directly; `apt`-installed `libnetcdf-dev` (what CI uses today, see
`.github/workflows/continuous-integration.yml:29`) historically does not
ship one. The plan is to vendor a small `cmake/FindNetCDF.cmake` module
(the well-known one from the NetCDF-Fortran project / CMake's own recipe
collection is a reasonable base) so `find_package(NetCDF REQUIRED)` works
uniformly across apt-installed, Homebrew, module-loaded (Snellius/DAS6),
and CMake-config NetCDF installs. This is new file infrastructure the repo
doesn't currently have, and is the one piece of real risk in this
sub-plan — see §7.

### 3.3 Target-scoped includes, definitions, and linking

Introduce one small `INTERFACE` library per shared include-dir group instead
of repeating `include_directories("../include" ...)` in every
`CMakeLists.txt`:

```cmake
# top-level CMakeLists.txt, after project()
add_library(rte_rrtmgp_headers INTERFACE)
target_include_directories(rte_rrtmgp_headers INTERFACE
  "${CMAKE_SOURCE_DIR}/include")

if(USECUDA)
  add_library(rte_rrtmgp_cuda_headers INTERFACE)
  target_include_directories(rte_rrtmgp_cuda_headers INTERFACE
    "${CMAKE_SOURCE_DIR}/include_kernels_cuda")
endif()
```

Then every library target links against these instead of restating paths:

```cmake
# src/CMakeLists.txt
add_library(rte_rrtmgp STATIC ${sourcefiles} aerosol_optics.cpp ../include/aerosol_optics.h)
target_link_libraries(rte_rrtmgp
  PUBLIC  rte_rrtmgp_headers
  PRIVATE rte_rrtmgp_kernels)
```

```cmake
# src_cuda/CMakeLists.txt
add_library(rte_rrtmgp_cuda STATIC ${sourcefiles_cuda})
target_link_libraries(rte_rrtmgp_cuda
  PUBLIC  rte_rrtmgp_headers rte_rrtmgp_cuda_headers
  PRIVATE rte_rrtmgp_kernels_cuda)
```

Because `target_link_libraries(... PUBLIC ...)` propagates include dirs
transitively, `src_test/CMakeLists.txt` no longer needs its own
`include_directories(${INCLUDE_DIRS} "../include" "../include_test" ...)`
line (`src_test/CMakeLists.txt:4`) — it gets `../include` for free from
linking `rte_rrtmgp`, and only needs to add its *own* directory
(`../include_test`) directly.

Global `add_definitions("-DUSECUDA")` (`CMakeLists.txt:48`) becomes
`target_compile_definitions()` on the specific targets that need it (the
CUDA libraries and any CPU code that branches on `#ifdef USECUDA`, e.g.
`include/optical_props.h` per the dedup plan) rather than every translation
unit in the build — this also makes it trivially greppable which targets
actually depend on the macro.

Third-party libs picked up via `find_package` get linked the same way,
replacing the flat `${LIBS}` list threaded through every config file:

```cmake
find_package(NetCDF REQUIRED)
find_package(HDF5 REQUIRED COMPONENTS C HL)
find_package(Boost REQUIRED)
if(USECUDA)
  find_package(CUDAToolkit REQUIRED)   # gives CUDA::curand, CUDA::cufft, ...
endif()
```

```cmake
# src_test/CMakeLists.txt
target_link_libraries(test_rte_rrtmgp_rt
  PRIVATE rte_rrtmgp rte_rrtmgp_cuda rte_rrtmgp_cuda_rt CUDA::curand NetCDF::NetCDF HDF5::HDF5)
```

replacing the bare `curand` (`src_test/CMakeLists.txt:32,38`) and the
`${LIBS}` variable built up piecemeal across every `config/*.cmake` file
(e.g. `config/das6.cmake`: `set(LIBS ${FFTW_LIB} ${FFTWF_LIB} ${NETCDF_LIB_C} ...)`).

### 3.4 Source lists: keep GLOB, but make it safe

Full explicit source lists are the "correct" fix, but this codebase adds
new `.cpp`/`.cu` files often enough (see the migration order in the
dedup plan, which deletes and adds files class-by-class) that hand-maintained
lists would create merge friction with that other refactor. Pragmatic
middle ground: switch every `FILE(GLOB ...)` to
`FILE(GLOB ... CONFIGURE_DEPENDS)`:

```cmake
FILE(GLOB sourcefiles CONFIGURE_DEPENDS "../src/*.cpp")
```

`CONFIGURE_DEPENDS` (CMake ≥ 3.12, available since this repo already
requires 3.18) makes the generated build system check the glob result on
every build, not just at configure time, which closes the "added a file,
forgot to rerun cmake" failure mode with a one-word change per file. If the
team later wants fully explicit lists (e.g. once the dedup refactor
stabilizes file counts), that's a follow-up, not a blocker here.

### 3.5 CTest integration

Add to the top-level `CMakeLists.txt`:

```cmake
enable_testing()
add_subdirectory(rfmip)   # or add_test() directly here if simpler
add_subdirectory(allsky)
```

with a minimal `CMakeLists.txt` in `rfmip/`/`allsky/` (new files) that
wraps the existing scripts:

```cmake
# rfmip/CMakeLists.txt
add_test(NAME rfmip_init COMMAND ${Python3_EXECUTABLE} rfmip_init.py
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME rfmip_run COMMAND ${Python3_EXECUTABLE} rfmip_run.py
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME rfmip_check
  COMMAND ${Python3_EXECUTABLE} compare-to-reference.py
    --ref_dir ${CMAKE_CURRENT_SOURCE_DIR}/../rrtmgp-data/examples/rfmip-clear-sky/reference
    --tst_dir ${CMAKE_CURRENT_SOURCE_DIR} --var rld rlu rsd rsu
    --file "r??_Efx_RTE-RRTMGP-181204_rad-irf_r1i1p1f1_gn.nc" --failure_threshold=5.8e-2
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
set_tests_properties(rfmip_run PROPERTIES DEPENDS rfmip_init)
set_tests_properties(rfmip_check PROPERTIES DEPENDS rfmip_run)
```

This turns `.github/workflows/continuous-integration.yml`'s hand-rolled
"Build / Run tests / Check results" shell steps into `cmake --build . &&
ctest --output-on-failure`, and gives local developers the same one-liner.
The `make_links.sh` symlink setup stays as-is (out of scope — it's data
staging, not a build step) and CI/developers still run it before `ctest`.

## 4. File layout changes

New files:

```
cmake/FindNetCDF.cmake                (vendored find module, see §3.2 caveat)
rfmip/CMakeLists.txt                  (ctest wrapper, new)
allsky/CMakeLists.txt                 (ctest wrapper, new)
```

Modified files (structure/mechanism changes, not line-by-line rewrites):

```
CMakeLists.txt                        option() calls, find_package() calls,
                                       INTERFACE header libraries, enable_testing()
src/CMakeLists.txt                    target_include_directories/target_link_libraries
src_cuda/CMakeLists.txt               same
src_cuda_rt/CMakeLists.txt            same (plumbing only, no source changes)
src_kernels/CMakeLists.txt            CONFIGURE_DEPENDS on the glob
src_kernels_cuda/CMakeLists.txt       target_include_directories
src_kernels_cuda_rt/CMakeLists.txt    target_include_directories
src_test/CMakeLists.txt               target_link_libraries with CUDA::curand, NetCDF::NetCDF, etc.
config/*.cmake (all 8)                strip hardcoded lib paths -> CMAKE_PREFIX_PATH hints;
                                       keep compiler selection & flags as-is
```

No files are deleted, no executable or library target is renamed.

## 5. Migration order

Unlike the CPU/GPU dedup plan, these changes are small and low-risk enough
to land as a handful of PRs rather than one-per-class, but they should
still be split so a regression is easy to bisect:

1. **`option()` declarations** (§3.1) — pure additive, zero behavior
   change, smallest possible PR, good first step to build confidence.
2. **Target-scoped includes/definitions/linking** (§3.3) — mechanical,
   no `config/*.cmake` changes needed yet since `${LIBS}`/`${INCLUDE_DIRS}`
   keep working during this step (just also linked via targets where
   convenient). Verify identical object/link output.
3. **`CONFIGURE_DEPENDS` on all globs** (§3.4) — one-line change per file,
   independent of everything else, can even land before/interleaved with
   step 2.
4. **CTest wrappers** (§3.5) — additive, doesn't touch existing CI steps
   yet; land this before step 5 so step 5 can be validated with `ctest`.
5. **`find_package` + vendored `FindNetCDF.cmake` + config-file path
   stripping** (§3.2) — the highest-risk step because it touches every
   machine's build inputs and needs access to (or a maintainer testing on)
   each cluster (`annuna`, `cloudy`, `das5`, `das6`, `snellius`) to
   confirm `CMAKE_PREFIX_PATH` hints resolve correctly. Do the two
   locally-testable configs first (`macbook_brew`, `macbook_brew_gcc`,
   `ubuntu_22lts` — the last one matches CI) and land those as one PR;
   send the cluster-specific config updates as follow-up PRs once someone
   with access to each machine can confirm the build (flag to Chiel van
   Heerwaarden / Menno Veerman per the maintainer contacts in the README,
   since they're the ones with cluster access).
6. **Fix the dead `CUDA_NVCC_FLAGS` in `config/das6.cmake`** (§1 item 8) —
   bundle this into step 5's das6 follow-up, since it's in the same file
   and the same person will be validating it.
7. **Update `.github/workflows/continuous-integration.yml`** to use
   `ctest` instead of the manual shell steps, once step 4 is in and
   verified to produce equivalent results — last, since it's the
   "flip the switch" step for the canonical build path everyone trusts.

## 6. Validation protocol

- After each step, do a **clean** `build/` reconfigure + build for at
  least: `macbook_brew` (or local dev equivalent) with default flags,
  `ubuntu_22lts` (matches CI), and `ubuntu_22lts -DUSECUDA=ON -DUSESP=ON`
  if CUDA hardware is available; otherwise confirm the CUDA configure step
  at least produces correct generated build files (`cmake -DSYST=... ` up
  to but not including `make`) since not everyone has a GPU locally.
- Run `rfmip`/`allsky` exactly as documented in the README (or via `ctest`
  once step 4 lands) and confirm `compare-to-reference.py` /
  `allsky_check.py` pass at the existing `--failure_threshold=5.8e-2`.
- For step 5 specifically: diff the `nm`/`otool -L` (or `ldd` on Linux)
  output of `test_rte_rrtmgp` before and after, to confirm it's linking
  against the *same* library files (not just "a" netcdf/hdf5, but the
  intended one) — this catches `find_package` silently picking up a wrong
  system-wide install on machines with multiple NetCDF versions.
- Confirm `cmake -LH` before/after step 1 to see the new help text appear
  for `USECUDA`/`USESP`/`USEMPI`/`SAFERNG`.
- No numerical output should change at any step — if it does, the change
  is wrong regardless of how "just build plumbing" it looks.

## 7. Risks and mitigations

- **No CMake-bundled NetCDF find module.** Mitigated by vendoring
  `cmake/FindNetCDF.cmake` (§3.2) rather than assuming
  `find_package(NetCDF)` works out of the box everywhere; validate against
  CI's apt-installed NetCDF first since that's the one environment
  guaranteed to be reproducible.
- **Cluster configs (`annuna`, `cloudy`, `das5`, `das6`, `snellius`) can't
  be validated in this environment** — no access to those machines. The
  plan explicitly sequences cluster-config changes as their own follow-up
  PRs (step 5/6) so they can be reviewed and tested by whoever has access,
  rather than blocking the generally-testable steps 1-4 on that
  availability.
- **`find_package` picking up a different library than the hardcoded path
  did**, silently changing which NetCDF/HDF5 build gets linked (different
  version, different feature flags). Mitigated by the `ldd`/`otool -L`
  diff check in §6 and by keeping `CMAKE_PREFIX_PATH` hints pointed at the
  exact same directories the old hardcoded paths came from.
- **CI currently only exercises `ubuntu_22lts` CPU build** — the
  `USECUDA`/`USESP`/`USEMPI` combinations touched by steps 1-3 are not
  covered by any automated check today. Worth a follow-up (separate from
  this plan) to extend CI's matrix, but not a blocker for this work
  since it's no less tested than before.
- **Scope creep into the CPU/GPU dedup plan.** These two plans touch some
  of the same files (`src/CMakeLists.txt`, `src_cuda/CMakeLists.txt`) for
  different reasons. Land whichever lands first, and rebase the other —
  don't try to design one CMakeLists change to anticipate the other plan's
  eventual file layout (e.g. don't pre-emptively restructure around `.tpp`
  files that don't exist yet).

## 8. Non-goals

- No change to which executables/libraries are produced, their names, or
  the documented `cmake -DSYST=... -DUSECUDA=...` invocation developers
  already use.
- No change to `src_cuda_rt/`, `include_rt/`, `src_kernels_cuda_rt/`,
  `include_rt_kernels/` *source* files, or to the ray-tracer executables'
  behavior — only their `CMakeLists.txt` gets the same generic
  target/glob/option treatment as everything else.
- No change to Fortran kernel build logic (`src_kernels/CMakeLists.txt`)
  beyond the `CONFIGURE_DEPENDS` glob fix.
- No attempt to make the project relocatable/installable via `install()` +
  exported targets (`find_package(rte-rrtmgp-cpp)` for downstream
  consumers) — this is an application repo with in-tree test drivers, not
  a library meant to be installed system-wide; out of scope unless a
  future need arises.
- No CI matrix expansion (adding `USECUDA`/`USESP` jobs) — flagged as a
  worthwhile follow-up in §7 but not part of this plan.
