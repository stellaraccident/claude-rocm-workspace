# ROCm Directory Map

This document maps out where all ROCm-related directories live on this system.

**Update the paths below to match your actual setup.**

## Environment Setup

**Python Environment:** Claude Code is launched with the project venv already active (symlinked as `venv/` in this workspace). This venv contains required build tools including:
- meson (for building simde, libdrm, and other meson-based dependencies)
- Other Python dependencies from requirements.txt

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

### Frameworks:

* JAX: `/develop/jax`
* XLA: `/develop/xla`

### Others:

* rocm-kpack: `/develop/rocm-kpack`

## Build Trees

### Active Builds
- **Main build:** `/develop/therock-build`
  - Configuration: Release
  - Target architecture: [gfx1201]
  - CMake flags:
  - Built ROCm installation is under `dist/rocm`
