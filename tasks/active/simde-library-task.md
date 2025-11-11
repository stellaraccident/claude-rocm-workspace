# Add simde library in third-party

**Status:** Completed
**Priority:** P1 (High)

## Overview

Could you please add the simde library https://github.com/simd-everywhere/simde in third-party libraries for TheRock. This would be an input dependency for both hip-runtime and rocr-runtime. Missing this library is currently blocking these two PRs as the TheRock-CI build check is now set to required:
ROCm/rocm-systems#500
ROCm/rocm-systems#1752

## Goals

- [x] Add the simde library to TheRock/third-party
- [x] Add as a dep to ROCR-Runtime
- [x] Add as a dep to clr
- [x] Make sure that the project builds without error up through clr

## Implementation

### Files Created/Modified

1. **`/develop/therock/third-party/simde/CMakeLists.txt`**
   - Dual-mode CMakeLists.txt following the libdrm pattern (meson-based)
   - Downloads simde 0.8.2 from GitHub (TODO: mirror to S3)
   - Invokes meson with arch-neutral, relocatable flags
   - Provides pkg-config interface (simde uses pkg-config, not CMake config)

2. **`/develop/therock/third-party/CMakeLists.txt`**
   - Added `add_subdirectory(simde)` in alphabetical order

3. **`/develop/therock/core/CMakeLists.txt`**
   - Added `therock-simde` to ROCR-Runtime BUILD_DEPS
   - Added `therock-simde` to hip-clr BUILD_DEPS

### Key Details

- **Build System**: simde uses Meson, so followed libdrm pattern with custom CMake wrapper
- **Dependency Type**: BUILD_DEPS (compile-time, header-only library)
- **Interface**: pkg-config via `INTERFACE_PKG_CONFIG_DIRS lib/pkgconfig`
- **Version**: 0.8.2
- **Headers Installed**: All simde headers including x86/ (sse2.h, avx.h, avx512.h), arm/, wasm/, mips/
- **Relocatable**: Yes, using `--prefix "/"`, `-Dpkgconfig.relocatable=true`, `-Dlibdir=lib`

### Verification

- ✅ simde builds successfully with meson
- ✅ pkg-config file is relocatable and works correctly
- ✅ All required headers (SSE2, AVX, AVX512) are installed
- ✅ ROCR-Runtime builds successfully with simde as BUILD_DEP
- ✅ hip-clr builds successfully with simde as BUILD_DEP

### Committed

Branch: `users/stellaraccident/add-simde-third-party`
Commit: `2a98c2508e8a9532be0a54a4e304306305203014`

Files changed:
- `core/CMakeLists.txt` - Added simde to ROCR-Runtime and hip-clr BUILD_DEPS
- `docs/development/dependencies.md` - Documented canonical usage via pkg-config
- `third-party/CMakeLists.txt` - Registered simde subdirectory
- `third-party/simde/CMakeLists.txt` - Meson-based build integration (new file)

### Pull Request

**PR #2081**: https://github.com/ROCm/TheRock/pull/2081
**Status**: Under Review

### Next Steps (Post-Merge)

- [ ] Mirror simde-0.8.2.tar.gz to S3 at `https://rocm-third-party-deps.s3.us-east-2.amazonaws.com/`
- [ ] Update URL in CMakeLists.txt after S3 mirror is complete

## Context

