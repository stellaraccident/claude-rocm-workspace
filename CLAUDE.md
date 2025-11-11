# ROCm Build Infrastructure Project

## Overview

This workspace is for build infrastructure work on ROCm (Radeon Open Compute) via the TheRock repository and related projects.

Project repository: https://github.com/ROCm/TheRock

## Working Environment

**Important:** See `directory-map.md` for all directory locations.

This is a meta-workspace. Actual source and build directories are scattered across the filesystem and referenced by absolute paths.

## Project Context

### What is ROCm?
ROCm is AMD's open-source platform for GPU computing. It includes:
- HIP (Heterogeneous-Interface for Portability) - CUDA alternative
- ROCm runtime and drivers
- Math libraries (rocBLAS, rocFFT, etc.)
- Developer tools and compilers

### Build Infrastructure Focus
As a build infra team member, typical work involves:
- CMake build system configuration
- CI/CD pipeline maintenance
- Build dependency management
- Cross-platform build support
- Build performance optimization
- Package generation and distribution

## Common Tasks

### Building
- Builds typically happen in separate build trees (see directory-map.md)
- Out-of-tree builds are standard practice
- Multiple build configurations (Release, Debug, RelWithDebInfo) often maintained simultaneously

### Source Navigation
- Source code is across multiple repositories and worktrees
- Git submodules are used extensively
- When editing build configs, check both source tree CMakeLists.txt and build tree caches

### Testing
- Unit tests, integration tests, and packaging tests
- Tests may run on different GPU architectures (gfx906, gfx908, gfx90a, etc.)

## Conventions & Gotchas

### Build System
- [Document your team's CMake conventions]
- [Note any non-standard build flags or requirements]

### Git Workflow
- [Document branching strategy]
- [Note how worktrees/submodules are used]

### Tools
- [List common tools: compilers, rocm-cmake, etc.]

## Reference

- [ROCm Documentation](https://rocm.docs.amd.com/)
- [TheRock repository](https://github.com/ROCm/TheRock)
- Internal wiki/docs: [add links]

## Notes

[Add your ongoing notes, discoveries, and context here as you work]
