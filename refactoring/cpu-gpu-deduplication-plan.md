# CPU/GPU deduplication refactoring plan

Status: proposed, not started
Scope: `src/` + `include/` (CPU) and `src_cuda/` + `src_kernels_cuda/` + `include/gpu/` (GPU two-stream) only.
Out of scope: the ray tracer (`src_cuda_rt/`, `include_rt/`, `src_kernels_cuda_rt/`, `include_rt_kernels/`) and its test drivers (`radiation_solver_rt.cu`, `radiation_solver_bw.cu`). Do not touch those directories as part of this effort.

This plan has been updated to reflect two changes made by `cmake-modernization-plan.md` (now fully implemented, see that document) since this plan was first drafted:
- The CUDA build option was renamed from the bare `USECUDA` variable to a proper `option(RTE_USE_CUDA ...)`; every `#ifdef`/`-D` below uses the new name.
- `include_kernels_cuda/` was merged into `include/gpu/` (which now also holds `tools_gpu.h`, `mem_pool_gpu.h`, and `tuner.h`, formerly loose in `include/`); every path below reflects the new location.

## 1. Problem recap

The CPU and GPU "two-stream" implementations are two independently maintained copies of the same nine physics classes (`Optical_props`, `Cloud_optics`, `Aerosol_optics`, `Gas_optics_rrtmgp`, `Rte_lw`, `Rte_sw`, `Fluxes`, `Gas_concs`, `Source_functions`), distinguished only by a `_gpu` suffix and by which `Array` type they store (`Array<T,N>` vs `Array_gpu<T,N>`). Measured overlap (`diff -u`, non-blank/non-comment lines that differ):

| Class | CPU lines | GPU lines | Differing lines |
|---|---|---|---|
| `gas_concs` | 117 | 80 | 81 |
| `source_functions` | 87 | 39 | 56 |
| `fluxes` | 197 | 136 | 153 |
| `optical_props` | 268 | 165 | 175 |
| `rte_lw` | 217 | 159 | 220 |
| `rte_sw` | 201 | 185 | 264 |
| `cloud_optics` | 232 | 329 | 339 |
| `aerosol_optics` | 224 | 279 | 423 |
| `gas_optics_rrtmgp` | 1356 | 1229 | 849 |

Root cause: every class's control flow (compute dimensions → allocate temporaries → call a kernel → repeat) is rewritten by hand for each backend. The two backends already expose near-identical kernel APIs (see §3.2) — the duplication lives entirely in the C++ orchestration layer sitting on top of them, not in the numerics.

Additionally, five CPU `.cpp` files (`optical_props.cpp`, `gas_optics_rrtmgp.cpp`, `fluxes.cpp`, `rte_sw.cpp`, `rte_lw.cpp`) each declare their own **file-local** `namespace rrtmgp_kernel_launcher { ... }` that adapts a handful of the Fortran `extern "C"` calls in `include/rrtmgp_kernels.h` (pointer-in, pointer-out) to by-value C++ signatures. This adapter is reinvented five times instead of once.

## 2. Goal

Reduce the CPU/GPU physics classes to **one implementation per class**, parameterized on a small "backend" policy, while:

- Keeping the existing public class names (`Optical_props`, `Optical_props_gpu`, `Cloud_optics`, `Cloud_optics_gpu`, ...) unchanged, so every call site in `src_test/`, `rfmip/`, `allsky/`, `rcemip/` keeps compiling with zero changes.
- Keeping CPU-only builds (`-DRTE_USE_CUDA=OFF`, the default, no `nvcc` available) working exactly as they do today — no new hard dependency on CUDA in `src/`.
- Keeping the CPU and GPU static libraries (`rte_rrtmgp`, `rte_rrtmgp_cuda`) as separate link targets, as they are today.
- Not changing the numerics. This is a structural refactor; RFMIP/all-sky/RCEMIP outputs must stay within today's `--failure_threshold` after every step.

## 3. Target architecture

### 3.1 Backend policy

Introduce a policy type per backend that supplies the array type and the kernel-call surface a class needs. Only the *type* is backend-specific; the algorithm written against it is not.

`include/backend_cpu.h` (new, plain C++, no CUDA):

```cpp
#ifndef BACKEND_CPU_H
#define BACKEND_CPU_H

#include "array.h"
#include "types.h"

struct Backend_cpu
{
    template<typename T, int N>
    using Array_t = Array<T, N>;
};

#endif
```

`include/gpu/backend_gpu.h` (new, only ever included from `src_cuda/*.cu` and `include/*.h` under `#ifdef RTE_USE_CUDA`):

```cpp
#ifndef BACKEND_GPU_H
#define BACKEND_GPU_H

#include "array.h"
#include "types.h"

struct Backend_gpu
{
    template<typename T, int N>
    using Array_t = Array_gpu<T, N>;
};

#endif
```

This is deliberately the *only* new abstraction at the array level — `Array`/`Array_gpu` themselves are already well factored (one file, `include/array.h`) and should not be touched.

### 3.2 Kernel bridge: one namespace per backend, identical signatures

The GPU side already exposes clean, by-value kernel-launcher namespaces in `include/gpu/*.h` (e.g. `Optical_props_kernels_cuda::increment_1scalar_by_1scalar(int ncol, int nlay, int ngpt, Float* tau_inout, const Float* tau_in)`), implemented in `src_kernels_cuda/*_launchers.cu`. Keep these as-is — they become the GPU half of the bridge.

For the CPU side, replace the five scattered file-local `rrtmgp_kernel_launcher` namespaces with **one header per physics class** under a new `include/kernel_launchers_cpu/` directory, each wrapping the relevant `rrtmgp_kernels::` Fortran calls with the identical by-value signature the GPU namespace already uses. Example, replacing the `rrtmgp_kernel_launcher` block currently duplicated inside `src/optical_props.cpp`:

`include/kernel_launchers_cpu/optical_props_kernels_cpu.h` (new):

```cpp
#ifndef OPTICAL_PROPS_KERNELS_CPU_H
#define OPTICAL_PROPS_KERNELS_CPU_H

#include "array.h"
#include "rrtmgp_kernels.h"
#include "types.h"

namespace Optical_props_kernels_cpu
{
    inline void increment_1scalar_by_1scalar(
            int ncol, int nlay, int ngpt,
            Float* tau_inout, const Float* tau_in)
    {
        rrtmgp_kernels::rte_increment_1scalar_by_1scalar(
                &ncol, &nlay, &ngpt, tau_inout, const_cast<Float*>(tau_in));
    }

    inline void increment_2stream_by_2stream(
            int ncol, int nlay, int ngpt,
            Float* tau_inout, Float* ssa_inout, Float* g_inout,
            const Float* tau_in, const Float* ssa_in, const Float* g_in)
    {
        rrtmgp_kernels::rte_increment_2stream_by_2stream(
                &ncol, &nlay, &ngpt,
                tau_inout, ssa_inout, g_inout,
                const_cast<Float*>(tau_in), const_cast<Float*>(ssa_in), const_cast<Float*>(g_in));
    }

    inline void inc_1scalar_by_1scalar_bybnd(
            int ncol, int nlay, int ngpt,
            Float* tau_inout, const Float* tau_in,
            int nbnd, const int* band_lims_gpoint)
    {
        rrtmgp_kernels::rte_inc_1scalar_by_1scalar_bybnd(
                &ncol, &nlay, &ngpt,
                tau_inout, const_cast<Float*>(tau_in),
                &nbnd, const_cast<int*>(band_lims_gpoint));
    }

    inline void inc_2stream_by_2stream_bybnd(
            int ncol, int nlay, int ngpt,
            Float* tau_inout, Float* ssa_inout, Float* g_inout,
            const Float* tau_in, const Float* ssa_in, const Float* g_in,
            int nbnd, const int* band_lims_gpoint)
    {
        rrtmgp_kernels::rte_inc_2stream_by_2stream_bybnd(
                &ncol, &nlay, &ngpt,
                tau_inout, ssa_inout, g_inout,
                const_cast<Float*>(tau_in), const_cast<Float*>(ssa_in), const_cast<Float*>(g_in),
                &nbnd, const_cast<int*>(band_lims_gpoint));
    }

    inline void delta_scale_2str_k(
            int ncol, int nlay, int ngpt,
            Float* tau_inout, Float* ssa_inout, Float* g_inout)
    {
        rrtmgp_kernels::rte_delta_scale_2str_k(
                &ncol, &nlay, &ngpt, tau_inout, ssa_inout, g_inout);
    }
}
#endif
```

This mirrors `include/gpu/optical_props_kernels_cuda.h` function-for-function. `inline` keeps these header-only (no new `.cpp` to add to `src/CMakeLists.txt`).

Then extend the backend policy to carry the kernel namespace:

```cpp
// backend_cpu.h
struct Backend_cpu
{
    template<typename T, int N> using Array_t = Array<T, N>;
    using Optical_props_kernels = Optical_props_kernels_cpu;
    // one alias per kernel namespace the templated classes need, added incrementally
    // as each class is migrated (see migration table in §5)
};

// backend_gpu.h
struct Backend_gpu
{
    template<typename T, int N> using Array_t = Array_gpu<T, N>;
    using Optical_props_kernels = Optical_props_kernels_cuda;
};
```

Do this incrementally, one class at a time (add the alias to both backend structs only when that class is migrated) rather than front-loading all nine aliases before any class is converted.

### 3.3 Class template pattern

Convert each duplicated class pair into a single template parameterized on `Backend`, keep the implementation in a header (`.tpp`, included at the bottom of the public header or from a small per-backend `.cpp`/`.cu`), and re-expose the historical names as aliases so nothing downstream changes.

Worked example for `Optical_props` (the base class every other physics class derives from — do this one first):

`include/optical_props.h` (rewritten):

```cpp
#ifndef OPTICAL_PROPS_H
#define OPTICAL_PROPS_H

#include <memory>
#include "array.h"
#include "types.h"
#include "backend_cpu.h"
#ifdef RTE_USE_CUDA
#include "backend_gpu.h"
#endif

template<typename Backend> class Optical_props_1scl_tmpl;
template<typename Backend> class Optical_props_2str_tmpl;

template<typename Backend>
void add_to(Optical_props_1scl_tmpl<Backend>& op_inout, const Optical_props_1scl_tmpl<Backend>& op_in);
template<typename Backend>
void add_to(Optical_props_2str_tmpl<Backend>& op_inout, const Optical_props_2str_tmpl<Backend>& op_in);

template<typename Backend>
class Optical_props_tmpl
{
    public:
        template<typename T, int N> using Array_t = typename Backend::template Array_t<T, N>;

        Optical_props_tmpl(
                const Array<Float,2>& band_lims_wvn,
                const Array<int,2>& band_lims_gpt);

        Optical_props_tmpl(const Array<Float,2>& band_lims_wvn);

        virtual ~Optical_props_tmpl() {};
        Optical_props_tmpl(const Optical_props_tmpl&) = default;

        Array<int,1> get_gpoint_bands() const { return this->gpt2band; }
        int get_nband() const { return this->band2gpt.dim(2); }
        int get_ngpt() const { return this->band2gpt.max(); }
        const Array<int,2>& get_band_lims_gpoint() const { return this->band2gpt; }
        const Array<Float,2>& get_band_lims_wavenumber() const { return this->band_lims_wvn; }

        // GPU-only accessors: no-ops to write, only meaningful for Backend_gpu.
        // See note below the code block on why these stay on the shared template.
        const Array_t<int,1>& get_gpoint_bands_device() const { return this->gpt2band_device; }
        const Array_t<int,2>& get_band_lims_gpoint_device() const { return this->band2gpt_device; }

    private:
        Array<int,2> band2gpt;
        Array<int,1> gpt2band;
        Array<Float,2> band_lims_wvn;
        Array_t<int,2> band2gpt_device;
        Array_t<int,1> gpt2band_device;
};

// ... Optical_props_arry_tmpl, Optical_props_1scl_tmpl, Optical_props_2str_tmpl
// follow the same pattern as today's classes, with Array<Float,3> replaced by
// Array_t<Float,3> everywhere.

#include "optical_props.tpp"

using Optical_props = Optical_props_tmpl<Backend_cpu>;
using Optical_props_arry = Optical_props_arry_tmpl<Backend_cpu>;
using Optical_props_1scl = Optical_props_1scl_tmpl<Backend_cpu>;
using Optical_props_2str = Optical_props_2str_tmpl<Backend_cpu>;

#ifdef RTE_USE_CUDA
using Optical_props_gpu = Optical_props_tmpl<Backend_gpu>;
using Optical_props_arry_gpu = Optical_props_arry_tmpl<Backend_gpu>;
using Optical_props_1scl_gpu = Optical_props_1scl_tmpl<Backend_gpu>;
using Optical_props_2str_gpu = Optical_props_2str_tmpl<Backend_gpu>;
#endif

#endif
```

`include/optical_props.tpp` (new; template method bodies, included by the header above — this is the file that used to be duplicated as `src/optical_props.cpp` + `src_cuda/optical_props.cu`):

```cpp
template<typename Backend>
Optical_props_tmpl<Backend>::Optical_props_tmpl(
        const Array<Float,2>& band_lims_wvn,
        const Array<int,2>& band_lims_gpt)
{
    Array<int,2> band_lims_gpt_lcl(band_lims_gpt);

    this->band2gpt = band_lims_gpt_lcl;
    this->band2gpt_device = this->band2gpt;
    this->band_lims_wvn = band_lims_wvn;

    this->gpt2band.set_dims({band_lims_gpt_lcl.max()});
    for (int iband=1; iband<=band_lims_gpt_lcl.dim(2); ++iband)
        for (int i=band_lims_gpt_lcl({1,iband}); i<=band_lims_gpt_lcl({2,iband}); ++i)
            this->gpt2band({i}) = iband;

    this->gpt2band_device = this->gpt2band;
}

// ... second constructor, unchanged body, template<typename Backend> prefix added.

template<typename Backend>
void Optical_props_2str_tmpl<Backend>::delta_scale(const Array_t<Float,3>& forward_frac)
{
    const int ncol = this->get_ncol();
    const int nlay = this->get_nlay();
    const int ngpt = this->get_ngpt();

    Backend::Optical_props_kernels::delta_scale_2str_k(
            ncol, nlay, ngpt,
            this->get_tau().ptr(), this->get_ssa().ptr(), this->get_g().ptr());
}

template<typename Backend>
void add_to(Optical_props_1scl_tmpl<Backend>& op_inout, const Optical_props_1scl_tmpl<Backend>& op_in)
{
    const int ncol = op_inout.get_ncol();
    const int nlay = op_inout.get_nlay();
    const int ngpt = op_inout.get_ngpt();

    if (ngpt == op_in.get_ngpt())
    {
        Backend::Optical_props_kernels::increment_1scalar_by_1scalar(
                ncol, nlay, ngpt,
                op_inout.get_tau().ptr(), op_in.get_tau().ptr());
    }
    else
    {
        if (op_in.get_ngpt() != op_inout.get_nband())
            throw std::runtime_error("Cannot add optical properties with incompatible band - gpoint combination");

        Backend::Optical_props_kernels::inc_1scalar_by_1scalar_bybnd(
                ncol, nlay, ngpt,
                op_inout.get_tau().ptr(), op_in.get_tau().ptr(),
                op_inout.get_nband(), op_inout.get_band_lims_gpoint().ptr());
    }
}

// add_to<Backend>(Optical_props_2str_tmpl<Backend>&, ...) follows the same shape.
```

Notes on the design decisions embedded in this example:

- **Note on `..._device` members.** Today only `Optical_props_gpu` carries a redundant device-side copy of `band2gpt`/`gpt2band` (`band2gpt_gpu`, `gpt2band_gpu`) so kernels can index it without a host→device round trip; the CPU class has no such field. In the template, `Array_t<int,2> band2gpt_device` becomes `Array<int,2>` for `Backend_cpu` — i.e. CPU pays for one harmless extra host-side copy of a tiny (nband-sized) array it already has host-side. This is a deliberate, cheap simplification: keeping the field conditionally present (`#ifdef` inside the template) is not worth the complexity it adds. If a reviewer objects to the extra copy, the alternative is a `if constexpr (std::is_same_v<Backend, Backend_gpu>)` guard around the two assignment lines instead of dropping the field — call this out in the PR description so the tradeoff is visible.
- `op_inout.get_tau().ptr()` on `Array<Float,3>` and `op_inout.get_tau().ptr()` on `Array_gpu<Float,3>` already return the same thing today (`Float*`/`const Float*`) — this is why the method bodies above are now **byte-identical** between backends, letter for letter what CPU's `rrtmgp_kernel_launcher::increment_1scalar_by_1scalar` and GPU's direct `Optical_props_kernels_cuda::increment_1scalar_by_1scalar(...)` call already did by hand.
- The `.tpp` is included directly by the `.h` (standard "templates in headers" practice), so there is no separate `.cpp`/`.cu` for `Optical_props` any more; delete `src/optical_props.cpp` and `src_cuda/optical_props.cu`.
- Explicit instantiation is *not* needed here because there's no separate translation unit to instantiate into — the template is instantiated wherever `Optical_props`/`Optical_props_gpu` is first used, exactly like any header-only template today (e.g. `Array<T,N>` itself). This avoids adding new files to either `CMakeLists.txt`.

### 3.4 Where the pattern needs to flex

Not every class is a pure copy. Two recurring asymmetries showed up while surveying the pairs; the template needs an escape hatch for both rather than forcing 100% unification:

1. **Backend-only constructors/conversions.** `Gas_concs_gpu` has a constructor `Gas_concs_gpu(const Gas_concs&)` (host→device upload) that has no CPU-side equivalent. Keep these as non-template, backend-specific free functions or constructors declared only inside `#ifdef RTE_USE_CUDA`, outside the shared template body — don't try to make the CPU class accept a no-op version of the same constructor.
2. **CPU-only I/O / bookkeeping methods.** A few CPU methods (e.g. `Gas_concs::set_vmr(name, Float)` scalar overload) exist because the CPU path reads scalars from NetCDF/TOML config directly, where the GPU path always receives a pre-expanded `Array`. Leave these as CPU-only additions on `Backend_cpu`'s instantiation, or as free functions taking `Optical_props&`-like references — do not force them into the shared template just for symmetry.

When a class hits one of these, prefer: shared template holds everything that is genuinely backend-symmetric; the small asymmetric surface is added back as a non-template member guarded by `if constexpr` or simply omitted from the template and re-added on the `Backend_cpu`/`Backend_gpu` alias via a thin wrapper subclass only if strictly necessary. Do not let one asymmetric method block templating the other 90% of a class.

## 4. Directory / file layout changes

```
include/
  backend_cpu.h                      new
  optical_props.h                    rewritten to Optical_props_tmpl<Backend>
  optical_props.tpp                  new (replaces src/optical_props.cpp body)
  cloud_optics.h / .tpp              same treatment
  aerosol_optics.h / .tpp
  fluxes.h / .tpp
  gas_concs.h / .tpp
  gas_optics_rrtmgp.h / .tpp
  rte_lw.h / .tpp
  rte_sw.h / .tpp
  source_functions.h / .tpp
  kernel_launchers_cpu/
    optical_props_kernels_cpu.h      new (replaces the 5 file-local rrtmgp_kernel_launcher blocks)
    cloud_optics_kernels_cpu.h
    aerosol_optics_kernels_cpu.h
    fluxes_kernels_cpu.h
    gas_optics_rrtmgp_kernels_cpu.h
    rte_lw_kernels_cpu.h
    rte_sw_kernels_cpu.h

include/gpu/
  backend_gpu.h                      new
  (existing *_kernels_cuda.h, tools_gpu.h, mem_pool_gpu.h, tuner.h unchanged)

src/
  aerosol_optics.cpp                 deleted (folded into .tpp)
  cloud_optics.cpp                   deleted
  fluxes.cpp                         deleted
  gas_concs.cpp                      deleted
  gas_optics_rrtmgp.cpp              deleted
  optical_props.cpp                  deleted
  rte_lw.cpp                         deleted
  rte_sw.cpp                         deleted
  source_functions.cpp               deleted

src_cuda/
  (the 9 matching .cu files)         deleted, same reasoning
```

Two follow-on consequences:

- `src/CMakeLists.txt`'s `FILE(GLOB sourcefiles "../src/*.cpp")` will glob to nothing once all nine `.cpp` files are deleted. CMake's `add_library` requires at least one source; keep `aerosol_optics.cpp`-equivalent structure by leaving one tiny placeholder `.cpp` (or, cleaner, switch `rte_rrtmgp` to an `INTERFACE` library once every class is migrated, since at that point it is header-only). Decide this at the end of the migration (§5), not up front — during the migration the glob will simply pick up fewer files each step, which is fine.
- Every include of `"optical_props.h"` etc. across `src_test/`, `rfmip/`, `allsky/` stays unchanged, because the type aliases preserve the old names.

## 5. Migration order

Migrate one class at a time, smallest/lowest-risk first, and run the full test suite (§6) after each. Suggested order, with the reason and rough effort:

| Order | Class | CPU / GPU lines | Why this position |
|---|---|---|---|
| 1 | `Optical_props` (base + 1scl + 2str) | 268 / 165 | Foundational — everything else derives from it; worked out in full above. |
| 2 | `Gas_concs` | 117 / 80 | Smallest; good second data point; exercises the "backend-only constructor" escape hatch (§3.4). |
| 3 | `Source_functions` | 87 / 39 | Smallest overall; low risk. |
| 4 | `Fluxes` | 197 / 136 | Exercises polymorphic subclasses (`Fluxes_broadband`, `Fluxes_byband`) — confirms the template pattern works through a second level of inheritance. |
| 5 | `Rte_lw` | 217 / 159 | First class that's a "driver" calling several kernels in sequence rather than a data container. |
| 6 | `Rte_sw` | 201 / 185 | Same shape as `Rte_lw`, do immediately after so the pattern is fresh. |
| 7 | `Cloud_optics` | 232 / 329 | GPU version has diverged further from CPU than earlier classes (highest line delta so far); expect more manual reconciliation. |
| 8 | `Aerosol_optics` | 224 / 279 | Same caution as `Cloud_optics`; note the two recent commits (`c44ffca`, `e3b3a79`) fixed a scattering edge case only in the ray-tracer copy — while touching this class, verify whether `src/aerosol_optics.cpp` and `src_cuda/aerosol_optics.cu` need the equivalent fix (zeroing `ssa`/`asy` when scattering is disabled); check with Menno Veerman before changing numerics. |
| 9 | `Gas_optics_rrtmgp` | 1356 / 1229 | Largest and most complex; do last, once the pattern has been proven on 8 smaller classes and the developer is fluent in it. Consider splitting this one into two PRs (interpolation/Planck-source path, then the two-stream/no-scattering solver path) rather than one large change. |

After step 9, revisit whether `rte_rrtmgp` (CPU) should become an `INTERFACE` library in `src/CMakeLists.txt` since no `.cpp` sources will remain — only do this if the Fortran kernel objects still link cleanly through `target_link_libraries(rte_rrtmgp rte_rrtmgp_kernels)`.

Each step is its own PR. Do not batch multiple classes into one PR — the value of this refactor is largely in the review being able to diff old-class-body vs new-template-body line by line and confirm no logic changed.

## 6. Validation protocol (run after every class migration)

1. Build both configurations from a clean `build/` directory:
   ```bash
   cmake -DSYST=<your config> -DCMAKE_BUILD_TYPE=DEBUG .. && cmake --build .
   cmake -DSYST=<your config> -DRTE_USE_CUDA=ON .. && cmake --build .
   ```
   A DEBUG CPU build first, to catch any newly-introduced undefined behavior (e.g. uninitialized `Array_t` reads) that RELEASE would optimize past.
2. Run the existing regression suite for both builds. `rfmip/` and `allsky/` are now wired up as `ctest` targets (`cmake-modernization-plan.md` §5 step 4) — after staging test data once (`./make_links.sh` + linking `test_rte_rrtmgp` in each directory, as documented in each directory's README), running
   ```bash
   ctest --output-on-failure
   ```
   from `build/` runs `rfmip_init` → `rfmip_run` → `rfmip_check` and `allsky_init` → `allsky_run` → `allsky_check` in dependency order, at the same `--failure_threshold=5.8e-2` the CI workflow uses. This replaces manually invoking `rfmip_init.py`/`rfmip_run.py`/`compare-to-reference.py`/`allsky_init.py`/`allsky_run.py`/`allsky_check.py` by hand, though those scripts still work standalone if you want to run just one of the two suites (`ctest -R rfmip` / `ctest -R allsky` also works).
   Run `rcemip` too if the migrated class is exercised by it (`Aerosol_optics`, `Cloud_optics`, `Gas_optics_rrtmgp` all are) — `rcemip` has no `ctest` wrapper, run it manually as before.
3. Since this refactor must not change numerics, prefer diffing CPU-build output against the pre-refactor CPU-build output directly (not just against the reference within threshold) for at least the first few migrations, to build confidence the template produces bit-identical results. A quick way: keep a copy of `build/` outputs from `main` before starting, and `nccmp` or `cdo diffn` the new outputs against them.
4. Confirm both `rte_rrtmgp` and `rte_rrtmgp_cuda` static libraries still build without either pulling in the other backend's headers unintentionally (a CPU-only build must never require `nvcc`/`-DRTE_USE_CUDA`). Simplest check: build the CPU-only configuration on a machine/container without CUDA installed, or grep the CPU build's compile commands for accidental `-DRTE_USE_CUDA`. The CI workflow's `build-cuda` job (`.github/workflows/continuous-integration.yml`) already builds the CUDA configuration on every push — a green run there covers the CUDA half of this check without needing local `nvcc`. (This job isn't documented in `cmake-modernization-plan.md`, which predates it — it was added afterward directly to the workflow file.)

## 7. Risks and mitigations

- **Risk: template errors are reported at instantiation site, not definition site**, making mistakes in a `.tpp` harder to debug than today's plain `.cpp`/`.cu`. Mitigation: after writing each `.tpp`, do a throwaway explicit instantiation (`template class Optical_props_tmpl<Backend_cpu>;` in a scratch `.cpp`) locally to get clean compiler errors before wiring it into the real headers.
- **Risk: `Array_t<Float,3>` silently resolves to the wrong backend** if a template parameter is dropped somewhere (e.g. a helper function forgets `template<typename Backend>` and hardcodes `Array<Float,3>`). Mitigation: the `Optical_props`/`Optical_props_gpu` aliases will fail to compile immediately if this happens (type mismatch at the alias), so this class of bug is caught at compile time, not silently — call this out to the reviewer as the actual safety net.
- **Risk: header bloat / compile time regression** from turning nine `.cpp`/`.cu` pairs into header-only templates instantiated in every translation unit that uses them. Mitigation: watch `make` wall-clock time after each migration step; if it regresses noticeably, fall back to explicit instantiation in one `.cpp`/`.cu` per backend per class (declare `extern template class Optical_props_tmpl<Backend_cpu>;` in the header, instantiate once in a `.cpp`) instead of pure header-only — this is a mechanical follow-up, not a redesign.
- **Risk: reconciling `Cloud_optics`/`Aerosol_optics`, which have already drifted** (largest CPU/GPU line deltas in the table in §1). Mitigation: when the CPU and GPU bodies genuinely disagree (not just renamed), do not silently pick one — flag the discrepancy to Menno Veerman/Chiel van Heerwaarden before merging, since it may be an existing latent bug in one backend (see the `c44ffca`/`e3b3a79` scattering-zeroing commits, which only patched the ray-tracer copy of this same logic).
- **Risk: scope creep into the ray tracer.** `include_rt/optical_props_rt.h` etc. are structurally identical to what's being deduplicated here but are explicitly out of scope for this pass. Do not template them as a "quick add-on" — that was intentionally deferred.

## 8. Non-goals

- No changes to `src_kernels/` (Fortran), `src_kernels_cuda/` kernel bodies (only their existing launcher headers are reused, not modified), or numerics anywhere.
- No changes to `src_cuda_rt/`, `include_rt/`, `src_kernels_cuda_rt/`, `include_rt_kernels/`, or the `_rt`/`_bw` test drivers.
- No change to public class names or method signatures used outside `src/`/`src_cuda/` (e.g. `src_test/radiation_solver.cpp`, `rfmip/`, `allsky/`, `rcemip/` should not need edits).
- `Array`/`Array_gpu` in `include/array.h` are not restructured — they're reused as-is via the `Backend::Array_t` alias.
