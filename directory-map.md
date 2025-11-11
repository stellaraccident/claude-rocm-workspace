# ROCm Directory Map

This document maps out where all ROCm-related directories live on this system.

**Update the paths below to match your actual setup.**

## Source Trees

### Main Repositories
- **TheRock main:** `/develop/therock`
  - Primary ROCm repository
  - Branch: main (or specify current branch)

### Submodules
Document key submodules if they're frequently edited:
- **rocm-libraries:** `/develop/therock/rocm-libraries`
- **rocm-systems:** `/develop/therock/rocm-systems`
- **llvm-project:** `/develop/therock/compiler/amd-llvm`
- **hipify:** `/develop/therock/compiler/hipify`

## Build Trees

### Active Builds
- **Main build:** `/develop/therock-build`
  - Configuration: Release
  - Target architecture: [gfx1201]
  - CMake flags:
  - Built ROCm installation is under `dist/rocm`
