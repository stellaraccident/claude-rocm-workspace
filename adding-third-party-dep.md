# Adding Third-Party Dependencies to TheRock

This guide documents how to add third-party dependencies to the TheRock super-project build system.

## Overview

TheRock is a CMake-based super-project that coordinates building many sub-projects. Third-party dependencies can be integrated using one of three patterns:

1. **Pattern 1: CMake-Native Libraries** - For libraries that use CMake and provide CMake config files
2. **Pattern 2: Meson-Based Header-Only Libraries** - For cross-platform meson libraries that use pkg-config
3. **Pattern 3: Meson-Based System Dependencies** - For OS-specific libraries needing special handling

## Choosing the Right Pattern

| Criteria | Pattern 1 (CMake) | Pattern 2 (Meson Header-Only) | Pattern 3 (Meson Sysdeps) |
|----------|-------------------|-------------------------------|---------------------------|
| **Build System** | CMake | Meson | Meson |
| **Interface** | CMake config (`Find*.cmake` or `*Config.cmake`) | pkg-config (`.pc` file) | pkg-config (`.pc` file) |
| **Location** | `/develop/therock/third-party/` | `/develop/therock/third-party/` | `/develop/therock/third-party/sysdeps/` |
| **Cross-platform** | Usually | Yes | OS-specific (linux/windows) |
| **Examples** | eigen, nlohmann-json, fmt | simde | libdrm, numactl, elfutils |
| **When to use** | Library provides CMake support | Header-only or no CMake support, uses pkg-config | Needs symbol renaming, patching, or OS-specific install |

## Key Concepts

### Build Phases
Each sub-project goes through 4 phases:
- **configure**: Initial CMake configuration
- **build**: Compilation (builds the `all` target)
- **stage**: Local install to `stage/` directory
- **dist**: Combined install merging this project's `stage/` with all runtime dependency `stage/` directories

### Dependency Types
- **BUILD_DEPS**: Must build/stage before configure phase (compile-time dependencies)
- **RUNTIME_DEPS**: Must build before AND must be in unified distribution tree at runtime

### Dependency Declaration Location
Dependencies are declared in `/develop/therock/core/CMakeLists.txt`, NOT in the sub-project's own CMakeLists.txt. This is because TheRock is a super-project that manages all dependency relationships.

## Pattern 1: Header-Only or CMake-Native Libraries

**Examples**: eigen, nlohmann-json, fmt

### Structure
Create `/develop/therock/third-party/<library>/CMakeLists.txt`:

```cmake
# Fetch the source tarball
# NOTE: Start with the original GitHub/upstream URL and add a TODO to mirror to S3.
# The tarball will be uploaded to S3 after initial testing.
therock_subproject_fetch(therock-<library>-sources
  CMAKE_PROJECT  # Optional: makes CMakeLists.txt visible to super-project
  # TODO: Mirror to https://rocm-third-party-deps.s3.us-east-2.amazonaws.com/<library>-<version>.tar.gz
  # Originally from: <upstream-url>
  URL <github-or-upstream-url>
  URL_HASH SHA256=<hash>
)

# Declare the sub-project
therock_cmake_subproject_declare(therock-<library>
  BACKGROUND_BUILD              # Run in job pool for parallelism
  EXCLUDE_FROM_ALL              # Don't build by default
  NO_MERGE_COMPILE_COMMANDS     # Skip compile_commands.json merging
  OUTPUT_ON_FAILURE             # Suppress output unless failure
  EXTERNAL_SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/source"
  CMAKE_ARGS                    # Optional: pass arguments to library's CMake
    -D<LIBRARY>_BUILD_TESTS=OFF
)

# Provide package for find_package() redirection
therock_cmake_subproject_provide_package(
  therock-<library> <PackageName> <relative/path/to/cmake/config>)

# Activate the sub-project
therock_cmake_subproject_activate(therock-<library>)

# Add to third-party meta-target
add_dependencies(therock-third-party therock-<library>)
```

### Register in Build System
Add to `/develop/therock/third-party/CMakeLists.txt`:
```cmake
add_subdirectory(<library>)
```

## Pattern 2: Meson-Based Header-Only Libraries

**Example**: simde

For meson-based header-only libraries that are cross-platform and don't need the rocm_sysdeps infrastructure.

### Key Differences from CMake Pattern

1. **pkg-config, not CMake config**: Use `INTERFACE_PKG_CONFIG_DIRS`, NOT `therock_cmake_subproject_provide_package()`
2. **Dual-mode CMakeLists.txt**: One file serves as both super-project integration and sub-project build script
3. **Meson invocation**: Must use specific flags for relocatable, arch-neutral builds
4. **DESTDIR installation**: Install using DESTDIR environment variable, not direct prefix

### Structure

Create `/develop/therock/third-party/<library>/CMakeLists.txt`:

```cmake
# Section 1: Super-project integration (when included from TheRock)
if(NOT CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  # CRITICAL: Detect meson in super-project context where venv PATH is available
  # The sub-project (Section 2) doesn't have access to the same environment,
  # so tool detection MUST happen here and be passed through CMAKE_ARGS.
  find_program(MESON_BUILD meson)
  if(NOT MESON_BUILD)
    message(FATAL_ERROR "Building <library> requires meson (install with: pip install meson)")
  endif()

  # Fetch the source tarball
  set(_source_dir "${CMAKE_CURRENT_BINARY_DIR}/source")
  set(_download_stamp "${_source_dir}/download.stamp")

  therock_subproject_fetch(therock-<library>-sources
    SOURCE_DIR "${_source_dir}"
    # TODO: Mirror to https://rocm-third-party-deps.s3.us-east-2.amazonaws.com/<library>-<version>.tar.gz
    # Originally from: <upstream-url>
    URL <github-or-upstream-url>
    URL_HASH SHA256=<hash>
    TOUCH "${_download_stamp}"
  )

  # Declare the sub-project (uses this same CMakeLists.txt as sub-build)
  therock_cmake_subproject_declare(therock-<library>
    EXTERNAL_SOURCE_DIR .
    BINARY_DIR build
    NO_MERGE_COMPILE_COMMANDS
    BACKGROUND_BUILD
    OUTPUT_ON_FAILURE
    CMAKE_ARGS
      "-DSOURCE_DIR=${_source_dir}"
      "-DMESON_BUILD=${MESON_BUILD}"  # Pass detected tool path to sub-project
      "-DPython3_EXECUTABLE=${Python3_EXECUTABLE}"
    INTERFACE_PKG_CONFIG_DIRS
      lib/pkgconfig
    EXTRA_DEPENDS
      "${_download_stamp}"
  )
  # Note: NO therock_cmake_subproject_provide_package() - library uses pkg-config
  therock_cmake_subproject_activate(therock-<library>)

  add_dependencies(therock-third-party therock-<library>)
  return()
endif()

# Section 2: Sub-project build (invoked by super-project)
cmake_minimum_required(VERSION 3.25)
project(<LIBRARY>_BUILD)

if(NOT MESON_BUILD)
  message(FATAL_ERROR "Missing MESON_BUILD from super-project")
endif()

# Meson refuses to build if source dir is subdir of build dir
set(PATCH_SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/../patch_source")

add_custom_target(
  meson_build ALL
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  COMMAND
    # Clean previous build
    "${CMAKE_COMMAND}" -E rm -rf -- "${CMAKE_INSTALL_PREFIX}" "${PATCH_SOURCE_DIR}"
  COMMAND
    # Copy sources (in case we need to patch in the future)
    "${CMAKE_COMMAND}" -E copy_directory "${SOURCE_DIR}" "${PATCH_SOURCE_DIR}"
  COMMAND
    # Meson setup - CRITICAL FLAGS for relocatable builds
    "${CMAKE_COMMAND}" -E chdir "${PATCH_SOURCE_DIR}"
    "${MESON_BUILD}" setup "${CMAKE_CURRENT_BINARY_DIR}"
      --reconfigure
      # We generate relocatable, arch neutral directory layouts
      --prefix "/"
      -Dpkgconfig.relocatable=true
      -Dlibdir=lib
      # Library-specific options (e.g., disable tests)
      -Dtests=false
  COMMAND
    # Build (may be minimal for header-only)
    "${MESON_BUILD}" compile --verbose
  COMMAND
    # Install using DESTDIR
    "${CMAKE_COMMAND}" -E env "DESTDIR=${CMAKE_INSTALL_PREFIX}" --
      "${MESON_BUILD}" install
)
```

### Critical Meson Flags

**Always use these flags for relocatable builds:**
- `--prefix "/"`: Set prefix to root (DESTDIR will provide actual location)
- `-Dpkgconfig.relocatable=true`: Makes .pc file use `${pcfiledir}` for paths
- `-Dlibdir=lib`: Ensures libraries go in `lib/` not `lib64/` or `lib/x86_64-linux-gnu/`

### Verification Steps

After building, verify the integration:

```bash
# 1. Check stage directory structure
ls -la /develop/therock-build/third-party/<library>/build/stage/

# Expected structure:
#   include/<library>/     # Headers
#   lib/pkgconfig/         # .pc file

# 2. Verify pkg-config file is relocatable
cat /develop/therock-build/third-party/<library>/build/stage/lib/pkgconfig/<library>.pc
# Should contain: prefix=${pcfiledir}/../..

# 3. Test pkg-config
PKG_CONFIG_PATH=/develop/therock-build/third-party/<library>/build/stage/lib/pkgconfig \
  pkg-config --cflags <library>
```

### Register in Build System
Add to `/develop/therock/third-party/CMakeLists.txt`:
```cmake
add_subdirectory(<library>)
```

## Pattern 3: Meson-Based System Dependencies

**Example**: libdrm

For system dependencies that need special handling, symbol renaming, or OS-specific installation.

### Structure
Create `/develop/therock/third-party/sysdeps/linux/<library>/CMakeLists.txt` with two sections:

#### Section 1: Super-Project Integration
```cmake
if(NOT CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    # Fetch sources
    set(_source_dir "${CMAKE_CURRENT_BINARY_DIR}/source")
    set(_download_stamp "${_source_dir}/download.stamp")

    therock_subproject_fetch(therock-<library>-sources
      SOURCE_DIR "${_source_dir}"
      URL "https://rocm-third-party-deps.s3.us-east-2.amazonaws.com/<library>-<version>.tar.gz"
      URL_HASH "SHA256=<hash>"
      TOUCH "${_download_stamp}"
    )

    # Declare sub-project (uses this same CMakeLists.txt as sub-build)
    therock_cmake_subproject_declare(therock-<library>
      EXTERNAL_SOURCE_DIR .
      BINARY_DIR build
      NO_MERGE_COMPILE_COMMANDS
      BACKGROUND_BUILD
      OUTPUT_ON_FAILURE
      CMAKE_ARGS
        "-DSOURCE_DIR=${_source_dir}"
        "-DMESON_BUILD=${MESON_BUILD}"
        "-DPython3_EXECUTABLE=${Python3_EXECUTABLE}"
      INSTALL_DESTINATION lib/rocm_sysdeps
      INTERFACE_LINK_DIRS lib/rocm_sysdeps/lib
      INTERFACE_INSTALL_RPATH_DIRS lib/rocm_sysdeps/lib
      INTERFACE_PKG_CONFIG_DIRS lib/rocm_sysdeps/lib/pkgconfig
      EXTRA_DEPENDS "${_download_stamp}"
    )
    therock_cmake_subproject_activate(therock-<library>)
    return()
endif()
```

#### Section 2: Sub-Project Build
```cmake
# Sub-project build logic
cmake_minimum_required(VERSION 3.25)
project(<LIBRARY>_BUILD)

# Invoke meson
add_custom_target(meson_build ALL
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  COMMAND "${CMAKE_COMMAND}" -E rm -rf -- "${CMAKE_INSTALL_PREFIX}"
  COMMAND "${MESON_BUILD}" setup "${CMAKE_CURRENT_BINARY_DIR}"
    --prefix "/"
    -Dlibdir=lib
    # ... meson options ...
  COMMAND "${MESON_BUILD}" compile --verbose
  COMMAND "${CMAKE_COMMAND}" -E env "DESTDIR=${CMAKE_INSTALL_PREFIX}" --
    "${MESON_BUILD}" install
)
```

### Register in Sysdeps
Add to `/develop/therock/third-party/sysdeps/linux/CMakeLists.txt`:
```cmake
add_subdirectory(<library>)
```

### Create THEROCK_BUNDLED_* Variable
In `/develop/therock/CMakeLists.txt`, add to the bundled variables section:
```cmake
set(THEROCK_BUNDLED_<LIBRARY>)  # Initialize as empty

if(THEROCK_BUNDLE_SYSDEPS)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(THEROCK_BUNDLED_<LIBRARY> therock-<library>)
  endif()
endif()
```

## Wiring Dependencies to Projects

Dependencies are declared in `/develop/therock/core/CMakeLists.txt`:

### For Regular Third-Party Libraries
```cmake
therock_cmake_subproject_declare(ROCR-Runtime
  ...
  BUILD_DEPS
    therock-<library>  # Add your library here
  ...
)
```

### For System Dependencies (via THEROCK_BUNDLED_* variables)
```cmake
therock_cmake_subproject_declare(ROCR-Runtime
  ...
  RUNTIME_DEPS
    ${THEROCK_BUNDLED_<LIBRARY>}  # Expands to library name or empty string
  ...
)
```

## Document the Dependency

**IMPORTANT**: After adding a new dependency, document the canonical way to use it in `/develop/therock/docs/development/dependencies.md`.

This file provides the standard way for ROCm projects to depend on the library. Add an entry in alphabetical order with:
- Brief description
- Canonical method (find_package or pkg_check_modules)
- Import library name
- Variables provided
- Alternative methods (if any)
- Any special notes

**Example for pkg-config based library:**
```markdown
## simde

SIMDe (SIMD Everywhere) is a header-only portability library for SIMD intrinsics.

- Canonical method: `pkg_check_modules(simde REQUIRED IMPORTED_TARGET simde)`
- Import library: `PkgConfig::simde`
- Vars: `simde_INCLUDE_DIRS`
- Alternatives: none
- Note: Header-only library, provides portable SIMD intrinsics (SSE, AVX, NEON, etc.)
```

**Example for CMake config based library:**
```markdown
## eigen

- Canonical method: `find_package(Eigen3)`
- Import library: `Eigen3::Eigen`
- Alternatives: none
```

This documentation ensures consistent usage across all ROCm projects.

## Key CMake Functions

### `therock_subproject_fetch(target_name)`
Downloads external content (like FetchContent).
- `URL`: Source tarball URL
- `URL_HASH`: SHA256 hash for verification
- `SOURCE_DIR`: Where to extract
- `TOUCH`: Stamp file for dependencies
- `CMAKE_PROJECT`: Makes CMakeLists.txt visible to super-project

### `therock_cmake_subproject_declare(target_name)`
Main function to declare a sub-project.
- `EXTERNAL_SOURCE_DIR`: Path to sources
- `BINARY_DIR`: Build directory
- `BUILD_DEPS`: Build-time dependencies (compile-time)
- `RUNTIME_DEPS`: Runtime dependencies (must be in dist tree)
- `CMAKE_ARGS`: Arguments passed to CMake
- `INSTALL_DESTINATION`: Subdirectory in stage/dist (e.g., `lib/rocm_sysdeps`)
- `INTERFACE_LINK_DIRS`: Advertise library directories to dependents
- `INTERFACE_INSTALL_RPATH_DIRS`: Advertise rpath directories
- `BACKGROUND_BUILD`: Run in job pool for parallelism
- `NO_MERGE_COMPILE_COMMANDS`: Skip compile_commands.json merging
- `OUTPUT_ON_FAILURE`: Suppress output unless failure
- `EXTRA_DEPENDS`: Additional dependencies (e.g., download stamps)

### `therock_cmake_subproject_provide_package(subproject_name package_name path)`
Advertises that this sub-project provides a find_package() package.
- Enables dependency provider to redirect `find_package()` calls
- Example: `therock_cmake_subproject_provide_package(ROCR-Runtime hsakmt lib/cmake/hsakmt)`

### `therock_cmake_subproject_glob_c_sources(subproject_name SUBDIRS ...)`
Tells super-project to watch source files for changes.
- Without this, changing sources won't trigger rebuild

### `therock_cmake_subproject_activate(subproject_name)`
Finalizes and activates the sub-project.
- Like `FetchContent_MakeAvailable()`
- Must be called last after all configuration

## Testing the Integration

### Configure
```bash
cmake -B /develop/therock-build -S /develop/therock -GNinja \
  -DTHEROCK_AMDGPU_FAMILIES=gfx1201 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
```

### Build Specific Component
```bash
cd /develop/therock-build
ninja <component>+expunge && ninja <component>+dist
```

## Common Gotchas

### General
1. **Dependencies are declared in core/CMakeLists.txt**, not in the sub-project's own CMakeLists.txt
2. **BUILD_DEPS vs RUNTIME_DEPS**: Use BUILD_DEPS for header-only libs, RUNTIME_DEPS for shared libraries
3. **THEROCK_BUNDLED_* pattern**: Required for optional system dependencies
4. **Download stamps**: Use `EXTRA_DEPENDS` with stamp files to ensure fetch completes first
5. **Dual-mode CMakeLists.txt**: For meson libraries, guard super-project logic with `if(NOT CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)`

### Meson-Specific
6. **Tool detection in super-project**: CRITICAL - Detect meson using `find_program()` in Section 1 (super-project), NOT in Section 2 (sub-project). The sub-project CMake invocation doesn't have access to the same shell environment/PATH as the super-project. Always pass detected tools via CMAKE_ARGS.
7. **Environment setup**: Before building, activate the venv: `source /develop/therock-venv/bin/activate`. This provides meson and other build tools. Without it, `find_program(meson)` will fail even though meson is in requirements.txt.
8. **pkg-config, not CMake**: Use `INTERFACE_PKG_CONFIG_DIRS`, NOT `therock_cmake_subproject_provide_package()` for meson libraries
9. **Critical meson flags**: Always use `--prefix "/"`, `-Dpkgconfig.relocatable=true`, `-Dlibdir=lib`
10. **DESTDIR installation**: Use `DESTDIR=${CMAKE_INSTALL_PREFIX}` when calling `meson install`
11. **Source directory location**: Meson refuses to build if source dir is a subdirectory of build dir (use PATCH_SOURCE_DIR)
12. **Verification**: Always check that .pc file contains `prefix=${pcfiledir}/../..` for relocatability
13. **Testing iterations**: Use `ninja <library>+expunge && ninja <library>` to fully rebuild from scratch

### Documentation
14. **No absolute paths in docs**: Never use absolute paths like `/develop/therock` in documentation files
15. **Avoid find_path**: Don't recommend `find_path()` for dependencies - it's fragile. Use `find_package()` or `pkg_check_modules()` only
16. **List "none" for alternatives**: If there are no good alternatives, explicitly state `- Alternatives: none`

## Reference Files

- Build system documentation: `/develop/therock/docs/development/build_system.md`
- Core dependency declarations: `/develop/therock/core/CMakeLists.txt`
- Third-party examples: `/develop/therock/third-party/`
- Sysdeps examples: `/develop/therock/third-party/sysdeps/linux/`
- CMake functions: `/develop/therock/cmake/therock_subproject.cmake`
