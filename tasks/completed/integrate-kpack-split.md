---
repositories:
  - therock
  - rocm-kpack
---

# Integrate ROCm KPACK Split into the Build System

**Status:** Complete - PR Ready
**Priority:** P0 (Critical)

## Overview

In prior tasks (ci-pipeline-shard.md) and the extended session which produced rocm-kpack, we created the ability to split artifacts into host and device specific shards and we re-organized the build system into generic and device-family specific build steps (see rocm-kpack `docs/tutorial_split_artifacts.md`).

This task integrates the kpack splitting functionality into TheRock's build system.

## Chosen Design: Build System Post-Processing with Shared Stage Prefixes

Integrate kpack splitting as artifact post-processing in the build system. Split artifacts share the same `stage/` directory prefixes as the original unsplit artifact, with content partitioned between generic (host) and device artifacts.

Key characteristics:
- `build/artifacts/` remains the canonical user interface
- Split happens automatically as part of `artifact+dist`
- Flag-guarded: `-DTHEROCK_KPACK_SPLIT_ARTIFACTS=ON`
- Same stage/ prefixes preserved - only content differs between split artifacts
- Bootstrap overlays generic + device artifacts into unified stage/

---

## Design Details

### Core Principle: Same Stage Prefixes, Partitioned Content

Split artifacts use the **same** `stage/` directory prefixes as the original unsplit artifact. The only difference is what content each artifact contains. This preserves all existing build system invariants.

### Build vs Bootstrap Invariants

| Phase | Stage Directory | Artifacts |
|-------|----------------|-----------|
| **Build** | Fat binaries (all archs in family) | Split into generic + per-arch |
| **Bootstrap** | Reconstituted (generic + target arch overlaid) | Input only, never re-export |

### Build Flow (THEROCK_KPACK_SPLIT_ARTIFACTS=ON)

```
1. Build as normal
   └── stage/ has fat binaries, all databases (unchanged)

2. artifact+dist populates intermediate location
   └── build/artifacts-unsplit/blas_lib_gfx110X-dgpu/

3. Split step creates final artifacts
   └── build/artifacts/
       ├── blas_lib_generic/
       ├── blas_lib_gfx1100/
       ├── blas_lib_gfx1101/
       └── blas_lib_gfx1102/
```

The `stage/` directory is **untouched** - no changes to the build graph.

### Bootstrap Flow (from split artifacts)

```
1. Fetch generic + device artifacts for target arch
   ├── blas_lib_generic.tar.zst
   └── blas_lib_gfx1100.tar.zst

2. Extract BOTH into stage/ (overlay, merge)
   └── stage/
       ├── lib/librocblas.so.5.2      ← from generic (host-only)
       ├── .kpack/blas_lib.kpm        ← from generic
       ├── .kpack/blas_lib_gfx1100.kpack  ← from device
       └── lib/rocblas/library/*.dat  ← from device

3. Create stage.prebuilt marker (once)

4. CMake sees .prebuilt, skips building
   └── find_package works, dlopen works, all invariants satisfied
```

### Artifact Structure After Split

**Original (unsplit)** - `blas_lib_gfx110X-dgpu`:
```
blas_lib_gfx110X-dgpu/
├── artifact_manifest.txt              # math-libs/BLAS/rocBLAS/stage
└── math-libs/BLAS/rocBLAS/stage/
    ├── lib/librocblas.so.5.2          # Fat binary (gfx1100, gfx1101, gfx1102)
    └── lib/rocblas/library/
        ├── TensileLibrary_lazy_gfx1100.dat
        ├── TensileLibrary_lazy_gfx1101.dat
        └── TensileLibrary_lazy_gfx1102.dat
```

**Generic** - `blas_lib_generic`:
```
blas_lib_generic/
├── artifact_manifest.txt              # math-libs/BLAS/rocBLAS/stage (SAME)
└── math-libs/BLAS/rocBLAS/stage/
    ├── lib/librocblas.so.5.2          # Host-only, with .rocm_kpack_ref marker
    ├── lib/rocblas/library/           # EMPTY (databases moved to device)
    └── .kpack/
        └── blas_lib.kpm               # Manifest listing available archs
```

**Device** - `blas_lib_gfx1100`:
```
blas_lib_gfx1100/
├── artifact_manifest.txt              # math-libs/BLAS/rocBLAS/stage (SAME)
└── math-libs/BLAS/rocBLAS/stage/
    ├── .kpack/
    │   └── blas_lib_gfx1100.kpack     # Extracted device code
    └── lib/rocblas/library/
        ├── TensileLibrary_lazy_gfx1100.dat
        └── TensileLibrary_lazy_gfx1100.co
```

**Key insight**: All artifacts reference the same stage/ prefix. They partition the content but preserve the directory structure.

---

## Critical Design Constraints Discovered

### 1. No Build Graph Changes

Options that would change find_package paths or stage directory locations would introduce dependency cycles:
- Sub-projects depend on upstream artifacts for find_package
- Artifacts depend on all their sub-projects being built
- Making sub-projects depend on artifact population creates cycles

**Solution**: Split happens AFTER build, doesn't affect stage/ directories used during build.

### 2. Runtime at Build Time

Some sub-projects may dlopen libraries during build. If device code were in separate stage directories, dlopen could fail or produce surprising results.

**Solution**: During build, stage/ has fat binaries (unchanged). Split only affects artifact output.

### 3. Bootstrap Must Reconstitute Complete stage/

Bootstrap from split artifacts must produce a stage/ directory that is functionally identical to what a full build would produce (minus other archs).

**Solution**: Extract generic + device artifacts into same stage/ prefix, overlaying content.

### 4. Never Re-Export Prebuilt Artifacts

If stage/ was populated from bootstrapped artifacts, don't run artifact population on it. This prevents incorrectly re-packaging split artifacts.

**Solution**: Document/enforce this rule. (Existing behavior already has this issue - it's bug, not feature.)

### 5. Bootstrapper Must Handle Shared Prefixes

Current bootstrapper assumes each artifact has exclusive ownership of its stage directories. With split artifacts, multiple artifacts contribute to the same stage/.

**Solution**: Change bootstrapper to merge/overlay instead of rm-then-extract:

```python
# Current (exclusive ownership)
for artifact in artifacts:
    for prefix in artifact.prefixes:
        rm_rf(prefix)           # Dangerous with shared prefixes!
        extract(artifact, prefix)

# New (shared ownership)
seen_prefixes = set()
for artifact in artifacts:
    for prefix in artifact.prefixes:
        if prefix not in seen_prefixes:
            rm_rf(prefix)       # Only clean first time
            seen_prefixes.add(prefix)
        extract(artifact, prefix)  # Overlay subsequent
```

---

## What Gets Split

**Source of truth**: `BUILD_TOPOLOGY.toml`, field `type = "target-specific"`

Target-specific artifacts (need splitting):
- **math-libs stage**: blas, fft, rand, prim, rocwmma, support, composable-kernel, miopen
- **comm-libs stage**: rccl

Target-neutral artifacts (bypass, no split):
- **foundation stage**: sysdeps, base, core-runtime
- **compiler-runtime stage**: amd-llvm, hip-runtime, ocl-runtime, profiler-core, etc.
- **dctools-core stage**: rdc

Generic stages may have device code (trap handlers, blitters) but as a product decision, these are declared architecture-agnostic and compiled for all known architectures. They don't need splitting.

---

## Alternatives Considered

### Alternative 1: Post-Build CI Step

Split artifacts in a separate CI job after the build completes, before compression/upload.

**Pros**: Clean separation of concerns, easy to debug (inspect before/after)

**Cons**: Extra CI step adds latency, more S3 storage during transition (both split and unsplit), splitting logic lives in CI rather than build system

**Rejected because**: Adds operational complexity and doesn't integrate cleanly with local development workflow.

### Alternative 2: Build-Time Sharding

Modify the build system to produce sharded artifacts directly during compilation.

**Pros**: No post-processing needed, direct output

**Cons**: Major CMake changes required, doesn't match how ROCm builds work (fat binaries are the natural output), would require changes to how device code compilation works

**Rejected because**: Too invasive, fights against the existing build model rather than working with it.

### Alternative 3: Separate Stage Directories (stage-host/, stage-gfx1100/)

During design, we considered having split artifacts use new stage directory names (e.g., `stage-host/`, `stage-gfx1100/`) to avoid any overlap.

**Pros**: Clean separation, no shared directories between artifacts

**Cons**:
- Breaks find_package paths (libraries would be in `stage-host/lib/` instead of `stage/lib/`)
- Would require CMake to adjust paths when split mode enabled, creating dependency cycles
- Some sub-projects dlopen libraries at build time - separate stage dirs would break this
- Significant changes to bootstrapper and build infrastructure

**Rejected because**: Introduces dependency cycles and breaks too many existing invariants. The simpler solution of keeping same prefixes with partitioned content preserves all existing behavior.

---

## Topology Extensions Needed

### 1. Database Lists

`split_artifacts.py` needs `--split-databases rocblas hipblaslt` to know which kernel database directories to partition by architecture.

**Proposed**: Add to BUILD_TOPOLOGY.toml per artifact:

```toml
[artifacts.blas]
type = "target-specific"
artifact_group = "math-libs"
split_databases = ["rocblas", "hipblaslt"]  # NEW

[artifacts.miopen]
type = "target-specific"
artifact_group = "ml-libs"
split_databases = ["miopen"]  # NEW
```

### 2. rocm-kpack Dependency

**Initial approach**: CMake variable for path to rocm-kpack:
```cmake
set(THEROCK_KPACK_DIR "" CACHE PATH "Path to rocm-kpack repository")
```

**Future**: Add rocm-kpack as git submodule to TheRock.

---

## Implementation Plan

### Phase 1: Topology Extensions
- Add `split_databases` field to BUILD_TOPOLOGY.toml
- Update build_topology.py to parse new field
- Update topology_to_cmake.py to expose database lists

### Phase 2: CMake Integration
- Add `THEROCK_KPACK_SPLIT_ARTIFACTS` option
- Add `THEROCK_KPACK_DIR` path variable
- Modify therock_artifacts.cmake:
  - Target-specific artifacts: populate to artifacts-unsplit/, run split, output to artifacts/
  - Target-neutral artifacts: populate directly to artifacts/

### Phase 3: Adapt split_artifacts.py
- Remove custom prefix synthesis logic (delete code)
- Keep same stage/ prefixes from input artifact
- Simplify to pure content partitioning

### Phase 4: Bootstrap Changes
- Update bootstrapper to handle shared stage/ prefixes
- Merge/overlay instead of rm-then-extract
- Test with split artifact bootstrap

### Phase 5: Testing
- Local build with split enabled
- Bootstrap from split artifacts
- Verify dlopen, find_package work
- CI integration (pre-submit with split, no reduce)

---

## Files to Modify

### TheRock Repository

| File | Changes |
|------|---------|
| `BUILD_TOPOLOGY.toml` | Add `split_databases` field per artifact |
| `build_tools/_therock_utils/build_topology.py` | Parse `split_databases` |
| `build_tools/topology_to_cmake.py` | Expose database lists to CMake |
| `cmake/therock_artifacts.cmake` | Split logic, two-step populate |
| `CMakeLists.txt` | Add `THEROCK_KPACK_SPLIT_ARTIFACTS`, `THEROCK_KPACK_DIR` |
| `build_tools/artifact_manager.py` | Handle shared prefixes in bootstrap |
| `build_tools/buildctl.py` | Bootstrap changes for overlay extraction |

### rocm-kpack Repository

| File | Changes |
|------|---------|
| `python/rocm_kpack/tools/split_artifacts.py` | Remove prefix synthesis, preserve stage/ paths |

---

## Open Items

1. **Exact split_artifacts.py changes**: Need to review current prefix logic and determine minimal changes
2. **Pre-commit testing**: Verify split artifacts work for single-arch testing without reduce phase
3. **Submodule timing**: When to add rocm-kpack as submodule vs path variable

---

## Session Log

### Session 1: Design Discussion (2025-12-08)

Reviewed prior work:
- ci-pipeline-shard task: BUILD_TOPOLOGY.toml, artifact_manager.py, stage targets
- rocm-kpack: split_artifacts.py, recombine_artifacts.py, tutorial docs

Evaluated three integration options, selected Option 3 (build-system post-processing).

Key design discoveries through rubber-ducking:
1. **Cycle problem**: Can't change find_package paths without creating build cycles
2. **Stage directory sharing**: Initially proposed separate stage-host/, stage-gfx1100/ dirs
3. **Linking problem**: Separate stage dirs break find_package and dlopen
4. **Final solution**: Keep same stage/ prefixes, partition content, overlay at bootstrap

Documented final design with:
- Same stage/ prefixes for all split artifacts
- Build flow: build → artifacts-unsplit → split → artifacts
- Bootstrap flow: fetch generic + device → overlay into stage/ → prebuilt marker
- Bootstrapper change: merge instead of rm-then-extract for shared prefixes

Ready for implementation pending approval.

### Session 2: Implementation (2025-12-09)

**PR Branch**: `users/stella/kpack_split_integration`
**Commit**: `3d270c9e` - Add kpack split integration for multi-arch artifact sharding

#### Implementation Summary

**Files Modified (5 files, +150/-2 lines):**

| File | Changes |
|------|---------|
| `BUILD_TOPOLOGY.toml` | Added `split_databases` to blas (`["rocblas", "hipblaslt"]`) and miopen (`["aotriton"]`) |
| `CMakeLists.txt` | Added `THEROCK_KPACK_SPLIT_ARTIFACTS` and `THEROCK_KPACK_DIR` options |
| `build_tools/_therock_utils/build_topology.py` | Added `split_databases` field to Artifact dataclass |
| `build_tools/topology_to_cmake.py` | Exposed `THEROCK_ARTIFACT_TYPE_*` and `THEROCK_ARTIFACT_SPLIT_DATABASES_*` variables |
| `cmake/therock_artifacts.cmake` | Implemented split logic in `therock_provide_artifact()` |

#### Key Implementation Details

**PYTHONPATH Setup**: rocm-kpack runs without pip install via:
```cmake
COMMAND "${CMAKE_COMMAND}" -E env "PYTHONPATH=${THEROCK_KPACK_DIR}/python"
  "${Python3_EXECUTABLE}" "${_split_tool}" ${_split_command_args}
```

**Bundler Path**: Uses dist/ not stage/ (includes runtime deps like libz):
```cmake
${THEROCK_BINARY_DIR}/compiler/amd-llvm/dist/lib/llvm/bin/clang-offload-bundler
```

**Dependency Chain**:
```
stage.stamp → unsplit manifest → split manifest (generic)
                                      ↓
                              [arch-specific artifacts derived]
```

Only generic manifest tracked in ninja. Arch-specific artifacts are derived outputs.

**Archive Generation**: Skipped for split artifacts (moves to upload phase in multi-arch CI).

#### Testing Results

Tested with RAND artifact on gfx1201. All 6 components split correctly:

| Component | Generic Output | Arch-specific Output |
|-----------|---------------|---------------------|
| rand_lib | Host .so libs + .kpm manifest | .kpack with kernels |
| rand_test | Test binaries + .kpm manifest | .kpack with kernels |
| rand_dev | Headers + cmake files | (empty - no device code) |
| rand_doc | Documentation | (empty - no device code) |
| rand_run | Runtime files | (empty - no device code) |
| rand_dbg | Debug files | (empty - no device code) |

**Output Structure**:
```
artifacts-unsplit/          # Input (original fat artifacts)
  rand_lib_gfx1201/
  rand_test_gfx1201/

artifacts/                  # Output (split artifacts)
  rand_lib_generic/         # Host-only: .so libs + .kpm manifest
  rand_lib_gfx1201/         # Arch-only: .kpack file
  rand_test_generic/        # Host-only: test binaries + .kpm
  rand_test_gfx1201/        # Arch-only: .kpack file
```

#### Fixes During Testing

1. **Argument name**: `--clang-offload-bundler` not `--bundler`
2. **Bundler path**: `dist/lib/llvm/bin/` not `stage/bin/` (dist has runtime deps)
3. **PYTHONPATH**: Added to cmake command so rocm_kpack imports work without pip install

#### Remaining Work (Out of Scope for This PR)

- **rocm-kpack PR**: Changes to preserve original stage prefixes instead of synthesizing `kpack/stage`
- **Bootstrap changes**: Update artifact_manager.py to handle shared stage/ prefixes (merge/overlay)
- **CI integration**: Enable split in pre-submit workflows

---

## Detailed Debugging: rand_lib Artifact Split

This section documents the exact artifact structure before and after splitting, tested on the `rand_lib` component with gfx1201 target.

### 1. Input: Unsplit Artifact

**Location**: `artifacts-unsplit/rand_lib_gfx1201/`

**artifact_manifest.txt**:
```
math-libs/rocRAND/stage
math-libs/hipRAND/stage
```

**Directory tree**:
```
rand_lib_gfx1201/
├── artifact_manifest.txt
└── math-libs
    ├── hipRAND
    │   └── stage
    │       └── lib
    │           ├── libhiprand.so -> libhiprand.so.1
    │           ├── libhiprand.so.1 -> libhiprand.so.1.1
    │           └── libhiprand.so.1.1          (18 KB, no device code)
    └── rocRAND
        └── stage
            └── lib
                ├── librocrand.so -> librocrand.so.1
                ├── librocrand.so.1 -> librocrand.so.1.1
                └── librocrand.so.1.1          (81 MB, FAT BINARY)
```

**Fat binary detection**: `librocrand.so.1.1` contains `.hip_fatbin` section (PROGBITS, 81 MB).

### 2. Output: Generic Artifact

**Location**: `artifacts/rand_lib_generic/`

**artifact_manifest.txt**:
```
math-libs/rocRAND/stage
math-libs/hipRAND/stage
```

**Directory tree**:
```
rand_lib_generic/
├── artifact_manifest.txt
└── math-libs
    ├── hipRAND
    │   └── stage
    │       └── lib
    │           ├── libhiprand.so -> libhiprand.so.1
    │           ├── libhiprand.so.1 -> libhiprand.so.1.1
    │           └── libhiprand.so.1.1          (18 KB, unchanged)
    └── rocRAND
        └── stage
            ├── .kpack
            │   └── rand_lib.kpm               (146 bytes, manifest)
            └── lib
                ├── librocrand.so -> librocrand.so.1
                ├── librocrand.so.1 -> librocrand.so.1.1
                └── librocrand.so.1.1          (52 MB, STRIPPED)
```

**Device code stripped**: `librocrand.so.1.1` reduced from 81 MB to 52 MB.
- `.hip_fatbin` section changed from `PROGBITS` to `NOBITS` (zeroed out)
- `.rocm_kpack_ref` marker injected pointing to `.kpack/rand_lib.kpm`

### 3. Output: Arch-Specific Artifact

**Location**: `artifacts/rand_lib_gfx1201/`

**artifact_manifest.txt**:
```
math-libs/rocRAND/stage
```

**Directory tree**:
```
rand_lib_gfx1201/
├── artifact_manifest.txt
└── math-libs
    └── rocRAND
        └── stage
            └── .kpack
                └── rand_lib_gfx1201.kpack     (1.8 MB, device kernels)
```

**Key insight**: The arch-specific artifact uses the **same prefix** (`math-libs/rocRAND/stage`) as the generic artifact. This is critical for overlay to work.

### 4. Overlay Simulation (Bootstrap)

When both artifacts are extracted to the same location (simulating bootstrap):

```bash
cp -a artifacts/rand_lib_generic/* /overlay/
cp -a artifacts/rand_lib_gfx1201/* /overlay/
```

**Result**:
```
/overlay/
├── artifact_manifest.txt                      (from arch, overwrites generic)
└── math-libs
    ├── hipRAND
    │   └── stage
    │       └── lib
    │           ├── libhiprand.so -> libhiprand.so.1
    │           ├── libhiprand.so.1 -> libhiprand.so.1.1
    │           └── libhiprand.so.1.1
    └── rocRAND
        └── stage
            ├── .kpack
            │   ├── rand_lib.kpm               ← from generic
            │   └── rand_lib_gfx1201.kpack     ← from arch-specific (MERGED!)
            └── lib
                ├── librocrand.so -> librocrand.so.1
                ├── librocrand.so.1 -> librocrand.so.1.1
                └── librocrand.so.1.1          (stripped, from generic)
```

**The `.kpack/` directory now contains both**:
- `rand_lib.kpm` - manifest listing available architectures
- `rand_lib_gfx1201.kpack` - actual device kernels for gfx1201

This merged structure is what the kpack runtime expects.

### 5. rocm-kpack Fixes Required

The original `artifact_splitter.py` had bugs that prevented correct overlay:

1. **Synthetic prefix bug**: Created kpack files under `kpack/stage/` instead of preserving original prefix
   - Before: `rand_lib_gfx1201/kpack/stage/.kpack/rand_lib_gfx1201.kpack`
   - After: `rand_lib_gfx1201/math-libs/rocRAND/stage/.kpack/rand_lib_gfx1201.kpack`

2. **Manifest overwrite bug**: Each prefix iteration overwrote the manifest instead of accumulating
   - Before: Only last prefix in manifest
   - After: All processed prefixes in manifest

3. **Symlink bug**: Symlinks were not copied to generic artifact
   - Before: Only `.so.1.1` files copied
   - After: All symlinks preserved (`.so` → `.so.1` → `.so.1.1`)
