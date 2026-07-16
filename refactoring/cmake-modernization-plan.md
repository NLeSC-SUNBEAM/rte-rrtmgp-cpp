# CMake modernization plan

Status: **implemented** (steps 1-7 complete as of 2026-07-16). This document
now doubles as the as-built record — sections below are annotated with what
actually shipped, including the places where the implementation narrowed or
extended the original proposal. See §5 for the step-by-step commit history
and §9 for a short summary of what changed along the way.

Scope: the CMake build system only (`CMakeLists.txt` at the repo root and in
`src/`, `src_cuda/`, `src_cuda_rt/`, `src_kernels/`, `src_kernels_cuda/`,
`src_kernels_cuda_rt/`, `src_test/`, plus the per-machine `config/*.cmake`
files). This was **orthogonal** to
[`cpu-gpu-deduplication-plan.md`](cpu-gpu-deduplication-plan.md) — it does
not move, rename, or merge any C++/CUDA/Fortran source file, and does not
change which `.cpp`/`.cu` files exist (that plan is still unstarted). No
source in `src_cuda_rt/`, `include_rt/`, `src_kernels_cuda_rt/`,
`include_rt_kernels/` changed, though its `CMakeLists.txt` got the same
generic treatment as everything else (target-based include dirs, explicit
source lists), since that's pure build plumbing, not "the ray tracer".

## 1. Problem recap

Inventory of what existed before this work started:

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
| `config/*.cmake` (10 files: `macbook_brew`, `macbook_brew_gcc`, `ubuntu`, `ubuntu_20lts`, `ubuntu_22lts`, `annuna`, `cloudy`, `das5`, `das6`, `snellius`) | per-machine compiler/library selection, `include()`-ed by `-DSYST=<name>` |

Concrete issues found, with locations (variable names below are the
*original* ones, e.g. `USECUDA` — see §9 for the rename that happened in
parallel with this work):

1. **Toggles weren't declared options.** `USECUDA`, `USESP`, `USEMPI`,
   `SAFERNG` were bare, undeclared variables checked with `if()`. No help
   text, no type, no validation. **Fixed in step 1.**

2. **No `find_package`, all library paths hand-written per machine.**
   Every `config/*.cmake` hardcoded absolute paths, e.g.
   `config/macbook_brew.cmake`: `set(NETCDF_LIB_C "/usr/local/lib/libnetcdf.dylib")`,
   `config/das6.cmake`: `"/opt/ohpc/pub/libs/gnu9/openmpi4/netcdf/4.7.3/lib/libnetcdf.so"`.
   **Fixed in step 5 for 7 of the 10 configs** — see §3.2 for why the other
   three were deliberately left alone.

3. **Global directory-scoped state instead of targets.**
   `include_directories()` and `add_definitions()` were used everywhere
   instead of `target_include_directories()` / `target_compile_definitions()`,
   and `target_link_libraries()` never used `PUBLIC`/`PRIVATE`/`INTERFACE`.
   **Fixed in step 2.**

4. **`FILE(GLOB ...)` for every source list**, CMake's best-known
   anti-pattern for missing a rebuild-trigger when files are added/removed.
   **Fixed in step 3** via `CONFIGURE_DEPENDS`.

5. **Compiler selection via `set(ENV{CXX} ...)` inside config files**,
   read before `project()` is called. Still present — this is a legitimate
   (if old-fashioned) way to select a compiler before `project()` runs,
   since CMake won't let you change `CMAKE_CXX_COMPILER` after that point.
   **Left as-is**; not part of this plan's scope.

6. **Hand-rolled cache-flag guard** (`HASCACHE`). Still present, unchanged;
   not part of this plan's scope.

7. **`curand` linked as a bare library name**, relying on the linker's
   default search path rather than `find_package(CUDAToolkit)` →
   `CUDA::curand`. **Not fixed** — explicitly out of scope for step 5, which
   was NetCDF/HDF5/Boost only (see §8).

8. **Stale `FindCUDA`-module variables mixed with native CUDA-language
   flags** in `config/das6.cmake` — `list(APPEND CUDA_NVCC_FLAGS ...)` was
   silently ignored since the top-level `CMakeLists.txt` reads
   `USER_CUDA_FLAGS`, not `CUDA_NVCC_FLAGS`. **Fixed in step 5/6** (bundled
   into the same das6.cmake change). This is a real behavior change on
   das6: `nvcc` now actually receives `-std=c++14 -arch=sm_80
   --expt-relaxed-constexpr`, which it silently never did before.

9. **No CTest integration.** `rfmip`/`allsky` ran via standalone shell/CI
   steps with no unified entry point. **Fixed in step 4.**

10. **CI only ever exercised one configuration** (`ubuntu_22lts`, CPU-only).
    Still true — extending CI's matrix was explicitly flagged as a
    follow-up, not part of this plan (see §8).

## 2. Goals

All of the below were achieved, with one deliberate scope reduction (config
migration limited to 7/10 files, per explicit instruction partway through
implementation — see §3.2):

- Replace ad-hoc variables with declared `option()`s. **Done.**
- Replace hardcoded per-machine library paths with `find_package()` calls,
  with per-machine `config/*.cmake` files reduced to compiler selection,
  optimization flags, and hints. **Done for 7 of 10 configs**
  (`macbook_brew`, `macbook_brew_gcc`, `ubuntu`, `ubuntu_20lts`,
  `ubuntu_22lts`, `das6`, `snellius`); `annuna`/`cloudy`/`das5` intentionally
  left untouched.
- Move directory-scoped `include_directories()`/`add_definitions()` to
  target-scoped equivalents. **Done.**
- Replace `FILE(GLOB ...)` with `CONFIGURE_DEPENDS`. **Done** (kept GLOB
  rather than fully-explicit lists, per the tradeoff in §3.4).
- Add `enable_testing()` + `add_test()` wrappers for rfmip/allsky.
  **Done**, and CI now uses them (step 7).
- Do all of this without changing which executables get built, their names,
  or the documented CLI invocation. **True** — `-DSYST=`/`-DRTE_USE_CUDA=`
  etc. all still work exactly as documented (module/definition names
  changed from `USECUDA`→`RTE_USE_CUDA` etc., but that rename happened in a
  parallel, closely-related effort — see §9 — not as part of "no API
  change" being broken).

## 3. Target architecture

### 3.1 Declared options in the top-level `CMakeLists.txt` — done

Implemented (commit `c6ade7b`), then the underlying variable names were
renamed project-wide from `USECUDA`/`USESP`/`USEMPI`/`SAFERNG` to
`RTE_USE_CUDA`/`RTE_USE_SP`/`RTE_USE_MPI`/`RTE_SAFE_RNG` in a closely
related but separate effort (commits `11f93d0`, `3249138`; see §9). Final
state:

```cmake
option(RTE_USE_CUDA "Build the CUDA (GPU) libraries and executables" OFF)
option(RTE_USE_SP   "Use single precision (32-bit) floats instead of double" OFF)
option(RTE_USE_MPI  "Use MPI compiler wrappers (mpicc/mpicxx/mpif90)" OFF)
option(RTE_SAFE_RNG "Use a safer but slower pseudo-RNG initialization" OFF)
```

`SYST` was also given a proper `CACHE STRING` entry with a docstring
(commit `3e7f9ce`), so it now shows up in `cmake -LH`/`ccmake` too.

### 3.2 `config/*.cmake` → compiler + flags + hints, not hardcoded paths — done for 7/10

Migrated: `macbook_brew`, `macbook_brew_gcc`, `ubuntu`, `ubuntu_20lts`,
`ubuntu_22lts`, `das6`, `snellius`. **Deliberately left untouched:**
`annuna`, `cloudy`, `das5` — explicit instruction partway through
implementation, since nobody working on this had access to those three
clusters to validate a change to them.

This required a design change from the original proposal: rather than a
single unconditional `find_package(NetCDF REQUIRED)` at the top level
(which would break the moment any untouched config's environment doesn't
put NetCDF on a `find_package`-discoverable path — a real risk for
environment-module-based clusters), the actual implementation guards the
whole `find_package` block on whether the loaded config already set the
legacy `NETCDF_LIB_C` variable:

```cmake
# CMakeLists.txt, after project()
if(NOT NETCDF_LIB_C)
  find_package(NetCDF REQUIRED)
  find_package(HDF5 REQUIRED COMPONENTS C)
  find_package(Boost REQUIRED)
endif()
```

`annuna`/`cloudy`/`das5` still set `NETCDF_LIB_C` themselves, so this block
— and every `target_link_libraries(... NetCDF::NetCDF ...)` call it
enables (each wrapped in `if(TARGET NetCDF::NetCDF)` /
`if(TARGET Boost::boost)` / `if(HDF5_FOUND)`) — is skipped entirely for
those three, with zero effect on them. This lets migrated and legacy
configs coexist in the same shared `CMakeLists.txt` files rather than
forking the build logic in two.

Example of a migrated config (`config/ubuntu_22lts.cmake`, abbreviated):

```cmake
set(CUB_INCLUDE_DIR "/usr/local/cuda/include")

# NetCDF/HDF5/Boost are located via find_package() in the top-level
# CMakeLists.txt; /usr is on CMake's default search path, no hint needed.
set(LIBS m z curl)
set(INCLUDE_DIRS ${CUB_INCLUDE_DIR})
```

Cluster example with EasyBuild module prefixes (`config/das6.cmake`,
abbreviated):

```cmake
list(APPEND CMAKE_PREFIX_PATH
  "/opt/ohpc/pub/libs/gnu9/openmpi4/netcdf/4.7.3"
  "/opt/ohpc/pub/libs/gnu9/openmpi4/hdf5/1.10.6"
  "/opt/ohpc/pub/libs/gnu9/openmpi4/boost/1.73.0")
set(LIBS "")
```

`config/snellius.cmake` uses the EasyBuild `EBROOT<PKG>` environment
variables (already relied on for `EBROOTCUDA` in that file) as
`CMAKE_PREFIX_PATH` hints instead of a fixed path, since the exact install
location varies by loaded module version:

```cmake
if(DEFINED ENV{EBROOTNETCDF})
  list(APPEND CMAKE_PREFIX_PATH "$ENV{EBROOTNETCDF}")
endif()
if(DEFINED ENV{EBROOTHDF5})
  list(APPEND CMAKE_PREFIX_PATH "$ENV{EBROOTHDF5}")
endif()
```

Also dropped in the migrated configs, confirmed unused by grepping the
actual C++/CUDA/Fortran source: `FFTW_LIB`/`FFTWF_LIB`/`IRC_LIB` (only ever
present in `das6.cmake`, nothing in this codebase calls FFTW or IRC
directly — leftover from a shared template with a sibling project) and
`SZIP_LIB` where it was already empty.

**Caveat realized in practice**: as anticipated, CMake has no bundled
NetCDF find module. The vendored `cmake/FindNetCDF.cmake` module (see §3.2
below → now §4) resolved this — validated directly against Homebrew NetCDF
(which does *not* export a discoverable config in the tested setup) via a
real `find_package(NetCDF REQUIRED)` → successful link → passing
`rfmip`/`allsky` numerical run.

**Unplanned addition**: `find_package(Boost)` on CMake ≥ 3.30 emits a
`CMP0167` dev warning ("The FindBoost module is removed"), since CMake is
deprecating its bundled `FindBoost.cmake` in favor of requiring Boost's own
exported CMake config. Fixed by explicitly setting the policy to `OLD`
(commit `af03359`), *not* `NEW`, specifically because EasyBuild-built Boost
on `das6`/`snellius` (built via `b2`, not CMake) is very unlikely to export
a `BoostConfig.cmake`, and `NEW` would force config-mode-only discovery.
This is a forward-compatibility risk that will resurface whenever CMake
actually deletes `FindBoost.cmake` outright (currently still shipped,
deprecated, as of CMake 4.3) — noted here for whoever picks it up next; no
action needed now.

### 3.3 Target-scoped includes, definitions, and linking — done

Implemented as designed (commit `e2781f0`): `rte_rrtmgp_headers` (carries
`include/`, plus `RTE_USE_CUDA`/`RTE_USE_SP` compile definitions),
`rte_rrtmgp_cuda_headers` (`include_kernels_cuda/`, later moved to
`include/gpu/` as part of the CPU/GPU header consolidation — see
`cpu-gpu-deduplication-plan.md`), and a third interface
library not in the original snippet — `rte_rrtmgp_rt_headers` (carries
`include_rt/` + `include_rt_kernels/`, plus `RTE_SAFE_RNG` — needed because
`src_cuda_rt`/`src_kernels_cuda_rt` had the same directory-scoped-include
problem as everything else, and were in scope as "pure build plumbing" per
this document's own scope note).

Every library now links these via `target_link_libraries(...
PUBLIC/PRIVATE ...)` instead of restating `include_directories()`, and
`src_test/CMakeLists.txt` picks up `include/` etc. transitively rather than
listing every directory itself — exactly as originally proposed. Also
fixed as a byproduct: the old `include_directories("../include" SYSTEM
${INCLUDE_DIRS})` had `SYSTEM` in the wrong argument position (must
immediately follow `[AFTER|BEFORE]`, before the first directory), so it was
silently being parsed as a literal, nonexistent directory named `SYSTEM`
rather than actually marking `${INCLUDE_DIRS}` as system includes. The new
`target_include_directories(<target> SYSTEM PRIVATE ${INCLUDE_DIRS})` calls
fix this for real.

Boost linking (needed once §3.2 confirmed `gas_optics_rrtmgp.cpp`/`.cu` use
`boost::trim` directly) was added to `src`, `src_cuda`, and `src_cuda_rt`
as part of step 5, each guarded with `if(TARGET Boost::boost)` for the same
legacy-config-coexistence reason as §3.2.

### 3.4 Source lists: keep GLOB, but make it safe — done

Implemented exactly as designed (commit `98ec597`): all 6
`FILE(GLOB ...)` calls (`src`, `src_cuda`, `src_cuda_rt`, `src_kernels`,
`src_kernels_cuda`, `src_kernels_cuda_rt`) now use `CONFIGURE_DEPENDS`.

### 3.5 CTest integration — done

Implemented as designed (commit `8cf4176`): `rfmip/CMakeLists.txt` and
`allsky/CMakeLists.txt` each wrap their `*_init.py` → `*_run.py` →
`*_check.py`/`compare-to-reference.py` pipeline as three named
`add_test()`s with `DEPENDS` chains. One implementation detail not
anticipated in the original design: `rfmip_check` invokes
`compare-to-reference.py` through `sh -c "..."` rather than a plain
`COMMAND` list, because its `--file` argument is a shell glob
(`r??_Efx_...nc`) that both the old `check_rfmip.sh` and CI relied on the
*shell* to expand — `add_test()`'s `COMMAND` does not invoke a shell, so
without this the pattern would have been passed through unexpanded and
matched nothing. Both wrappers also set `RRTMGP_ROOT`/`RRTMGP_DATA` as
test-level `ENVIRONMENT`, matching CI's job-level env — required because
`allsky_check.py`'s `--ref_dir` default reads
`os.environ["RRTMGP_DATA"]` unconditionally at argparse-construction time.

`rcemip` was intentionally left out, matching the fact that it isn't in CI
either and has a different, unexamined script structure
(`test_rcemip_input.py`/`test_rcemip_input_rt.py`).

## 4. Directory / file layout changes — final

New files:

```
cmake/FindNetCDF.cmake                (vendored find module — CMake has no bundled
                                       one, and not every NetCDF install ships its
                                       own config file)
rfmip/CMakeLists.txt                  (ctest wrapper)
allsky/CMakeLists.txt                 (ctest wrapper)
```

Modified files:

```
CMakeLists.txt                        option() calls, CMP0167 policy, find_package()
                                       calls (guarded), INTERFACE header libraries,
                                       enable_testing()
src/CMakeLists.txt                    target_include_directories/target_link_libraries,
                                       Boost::boost
src_cuda/CMakeLists.txt               same, + Boost::boost
src_cuda_rt/CMakeLists.txt            same, + Boost::boost (plumbing only, no source changes)
src_kernels/CMakeLists.txt            CONFIGURE_DEPENDS on the glob
src_kernels_cuda/CMakeLists.txt       target_include_directories/target_link_libraries
src_kernels_cuda_rt/CMakeLists.txt    target_include_directories/target_link_libraries
src_test/CMakeLists.txt               target_link_libraries with NetCDF::NetCDF,
                                       HDF5_LIBRARIES, Boost::boost (guarded); per-executable
                                       target_include_directories/target_compile_definitions
config/macbook_brew.cmake             hardcoded paths -> CMAKE_PREFIX_PATH hints
config/macbook_brew_gcc.cmake         same
config/ubuntu.cmake                   same (no hint needed, /usr is default)
config/ubuntu_20lts.cmake             same
config/ubuntu_22lts.cmake             same
config/das6.cmake                     same + fixed dead CUDA_NVCC_FLAGS bug
config/snellius.cmake                 same, using EBROOTNETCDF/EBROOTHDF5 hints
.github/workflows/continuous-integration.yml   Build/Run-tests/Check-results collapsed
                                       into Build/Stage-test-data/Run-tests(ctest) --
                                       uncommitted as of this writing, see §5 step 7
```

Untouched, by explicit instruction: `config/annuna.cmake`,
`config/cloudy.cmake`, `config/das5.cmake`.

No files were deleted, no executable or library target was renamed.

## 5. Migration order — as executed

All 7 steps are implemented. Commit hashes below are on branch
`develop-refector`.

1. **`option()` declarations** (§3.1) — `c6ade7b`. ✅
2. **Target-scoped includes/definitions/linking** (§3.3) — `e2781f0`. ✅
   Verified via a clean configure + inspection of the generated
   `flags.make`/compile commands, and a direct recompile of
   `aerosol_optics.cpp`/`radiation_solver.cpp` with the generated flags.
3. **`CONFIGURE_DEPENDS` on all globs** (§3.4) — `98ec597`. ✅
4. **CTest wrappers** (§3.5) — `8cf4176`. ✅ Verified via `ctest -N`,
   `ctest --show-only=json-v1` (confirmed DEPENDS chains and ENVIRONMENT
   properties), and an actual `ctest` run (correctly failed for
   environment-staging reasons — missing Python packages, un-run
   `make_links.sh` — not harness bugs).
5. **`find_package` + vendored `FindNetCDF.cmake` + config-file path
   stripping** (§3.2) — `788e094`, with a follow-up `c928335` (the new
   `cmake/FindNetCDF.cmake` file was missed by the original `git add` and
   had to be committed separately after it broke a build on snellius — see
   §9), and `af03359` (CMP0167 policy fix, prompted by a warning seen
   during that same snellius validation). **Scope note**: narrowed from
   "all config files" to 7 of 10 by explicit instruction —
   `annuna`/`cloudy`/`das5` deliberately excluded, no access to validate
   those clusters. ✅ Verified with a full clean build (Homebrew NetCDF/
   Boost installed for the purpose, `rte-rrtmgp`/`rrtmgp-data` submodules
   checked out) through actual linking, confirmed via `otool -L` that the
   executable links the real NetCDF/HDF5 dylibs, then a full `ctest` pass
   with real reference data (all 6 tests green).
6. **Fix the dead `CUDA_NVCC_FLAGS` in `config/das6.cmake`** (§1 item 8) —
   bundled into step 5's commit `788e094`, as planned. ✅ Not independently
   testable here (no CUDA hardware); flagged to validate on das6 directly,
   since it's a real behavior change (flags that were silently dropped
   before are now actually applied to `nvcc`).
7. **Update `.github/workflows/continuous-integration.yml`** to use
   `ctest` — implemented and validated locally (full build → stage data →
   `ctest`, all 6 tests passing, exactly mirroring the new CI steps), but
   **not yet committed** as of this writing.

## 6. Validation protocol — executed

- Clean CPU-only builds (`macbook_brew`) were run repeatedly through this
  work, from `cmake -S ... -B ...` through `cmake --build .` and
  `ctest --output-on-failure`, including one full run with real dependencies
  (Homebrew NetCDF/HDF5/Boost, checked-out `rte-rrtmgp`/`rrtmgp-data`
  submodules, `netCDF4`/`xarray`/`dask` installed) producing **6/6 passing
  tests** against real reference data at the existing
  `--failure_threshold=5.8e-2`.
- A pre-existing, unrelated Fortran module-ordering failure was hit
  (`mo_fluxes_byband_kernels.F90` failing to find `mo_rte_kind.mod`) and
  confirmed via `git stash` to reproduce identically on pre-refactor code —
  root cause turned out to simply be the `rte-rrtmgp` submodule not being
  checked out in the sandbox used for validation, not a CMake bug.
- `RTE_USE_CUDA=ON` was validated by the user directly on hardware with a
  CUDA toolkit (not reproducible in the sandbox used for most of this
  work), which surfaced the `__CUDACC__`/`RTE_USE_CUDA` regression fixed
  outside this plan's scope (see §9) and, later, the snellius
  `FindNetCDF.cmake`/`CMP0167` issues addressed above.
- `das6`/`snellius` themselves were not independently build-tested by
  whoever implemented this (no cluster access) — the das6
  `CUDA_NVCC_FLAGS` fix and the general NetCDF/HDF5/Boost hint changes on
  both clusters should be validated by someone with access before being
  fully trusted.
- No numerical output changed at any step, confirmed by the passing
  `rfmip_check`/`allsky_check` runs against the existing reference data and
  threshold.

## 7. Risks and mitigations — outcomes

- **No CMake-bundled NetCDF find module.** *Materialized as expected*;
  mitigated exactly as planned via the vendored `cmake/FindNetCDF.cmake`.
  Validated against Homebrew NetCDF.
- **Cluster configs (`annuna`, `cloudy`, `das5`) can't be validated in this
  environment.** *Resolved by scope reduction*, not mitigation — excluded
  from migration entirely rather than migrated-but-unverified.
- **`find_package` picking up a different library than the hardcoded path
  did.** *Did not materialize* in the environment this was validated in
  (confirmed via `otool -L` that the linked NetCDF/HDF5 were the intended
  Homebrew ones) — still worth the same check on first use on each newly
  migrated machine (`ubuntu*`, `das6`, `snellius`).
- **CI currently only exercises `ubuntu_22lts` CPU build.** *Still true*,
  unchanged by this work; remains a follow-up.
- **Scope creep into the CPU/GPU dedup plan.** *Did not occur* — no
  physics source files were touched by this work.
- **New, not anticipated in the original plan — uncommitted new file.**
  `cmake/FindNetCDF.cmake` was created but not `git add`ed alongside the
  rest of step 5's commit, so it silently didn't exist on any machine that
  pulled that commit — surfaced as a hard CMake configure failure on
  snellius (`find_package(NetCDF)` falling back to CONFIG mode and
  failing, since MODULE mode couldn't find the missing file). Fixed by a
  follow-up commit (`c928335`). **Lesson for next time**: after any step
  that adds a *new* file (not just edits), explicitly confirm `git status`
  shows it staged before considering the step done — a passing local build
  does not catch a file that exists locally but was never committed.
- **New, not anticipated in the original plan — `CMP0167`/`FindBoost`
  forward-compatibility.** See §3.2. Not blocking; noted for whoever
  revisits this once CMake fully removes `FindBoost.cmake`.

## 8. Non-goals — held

- No change to which executables/libraries are produced, their names, or
  the documented `-DSYST=... -DRTE_USE_CUDA=...` invocation. **Held.**
- No change to `src_cuda_rt/`, `include_rt/`, `src_kernels_cuda_rt/`,
  `include_rt_kernels/` *source* files. **Held** — only their
  `CMakeLists.txt` changed.
- No change to Fortran kernel build logic beyond `CONFIGURE_DEPENDS`.
  **Held.**
- No `install()`/exported-targets support. **Held**, not attempted.
- No CI matrix expansion. **Held**, not attempted — still a good follow-up
  for someone else to pick up.
- `find_package(CUDAToolkit)` / `CUDA::curand` replacing the bare `curand`
  link, and CUB via `CMAKE_PREFIX_PATH` instead of a hardcoded path in
  `ubuntu_22lts.cmake` — **out of scope**, not attempted; natural follow-up
  to step 5 if someone wants to close the remaining item in §1's issue list
  (#7).

## 9. Related work done in parallel (not part of this plan, but touching the same files)

Between steps 1 and 2 of this plan, a separate but closely related cleanup
happened: the ad-hoc `USECUDA`/`USESP`/`USEMPI`/`SAFERNG` variable names
introduced by step 1 (still literally named that at the time) were renamed
project-wide to `RTE_USE_CUDA`/`RTE_USE_SP`/`RTE_USE_MPI`/`RTE_SAFE_RNG`
(commits `11f93d0`, `3249138`), including every `#ifdef`/`#if defined(...)`
guard in `include/*.h` and `include_rt/*.h` that referenced the old macro
names, plus the matching `config/*.cmake` references. This is why all code
snippets in this document now use the new names even where the original
proposal (written before that rename) used the old ones.

That rename briefly broke CUDA-enabled builds: `include/array.h` had used
`#ifdef __CUDACC__` (true only when `nvcc` compiles a translation unit) to
guard `Array_gpu`'s CUDA-runtime-dependent code, and a commit
(`5e700d2`) mistakenly widened that specific guard to `#ifdef RTE_USE_CUDA`
too (true for *every* target once the CMake option is `ON`, including the
CPU library `rte_rrtmgp`, which is always compiled with a plain C++
compiler, never `nvcc`). This pulled `tools_gpu.h` (which needs
`cudaError`/`cudaMalloc`/etc. from the real CUDA runtime) into a plain
`g++`/`clang++` compile whenever a CUDA-enabled build was configured. Fixed
by reverting just `include/array.h`'s 19 guards back to `__CUDACC__`
(commit `f678130`) — the only file where this distinction actually
mattered, since every other consumer of the `RTE_USE_CUDA`-guarded
`#ifdef`s in `include_rt/*.h`/`include_test/*.h` is exclusively compiled by
`nvcc` anyway, given the directory-scoped include paths involved.
