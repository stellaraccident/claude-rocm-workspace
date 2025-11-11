# ROCm Directory Map

This document maps out where all ROCm-related directories live on this system.

**Update the paths below to match your actual setup.**

## Source Trees

### Main Repositories
- **TheRock main:** `/path/to/TheRock`
  - Primary ROCm repository
  - Branch: main (or specify current branch)

- **HIP repository:** `/path/to/HIP`
  - Branch/worktree info

- **ROCm-Device-Libs:** `/path/to/ROCm-Device-Libs`
  - Device-side libraries

### Git Worktrees
- **Feature branch worktree:** `/path/to/worktree/feature-name`
  - Purpose: [describe what you're working on]
  - Branch: feature-branch-name

- **Experimental worktree:** `/path/to/worktree/experiment`
  - Purpose: [testing/development]

### Submodules
Document key submodules if they're frequently edited:
- **Submodule name:** `TheRock/path/to/submodule` -> actual location

## Build Trees

### Active Builds
- **Main build (Release):** `/path/to/builds/rocm-main`
  - Configuration: Release
  - Target architecture: [gfx906, gfx908, etc.]
  - CMake flags: [note any important flags]

- **Debug build:** `/path/to/builds/rocm-debug`
  - Configuration: Debug
  - Purpose: debugging and development

- **Clean build:** `/path/to/builds/rocm-clean`
  - For testing clean builds

### CI/Testing Builds
- **CI build sandbox:** `/path/to/ci-builds/rocm-ci`
  - Purpose: CI pipeline testing
  - Usually temporary

- **Packaging test build:** `/path/to/builds/rocm-package-test`
  - For testing package generation

## Installation Directories

- **System ROCm install:** `/opt/rocm`
  - System-wide ROCm installation (if applicable)

- **Local test install:** `/path/to/local/rocm-install`
  - Local installation for testing

## Other Important Directories

- **Scripts/Tools:** `/path/to/rocm-scripts`
  - Custom build/test scripts

- **Test data:** `/path/to/rocm-test-data`
  - Large test datasets (if separate)

- **Documentation build:** `/path/to/rocm-docs-build`
  - Generated documentation

## Quick Reference

When working with Claude Code from this workspace, reference these directories by their absolute paths:

```bash
# Example: Read a CMakeLists.txt from TheRock
Read("/path/to/TheRock/CMakeLists.txt")

# Example: Check build output
Read("/path/to/builds/rocm-main/CMakeCache.txt")
```

## Notes

- Update this map whenever you create new worktrees or build directories
- Note which directories are temporary vs. permanent
- Document any unusual directory structures or symlinks
