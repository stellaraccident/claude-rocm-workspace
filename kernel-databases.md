# ROCm Kernel Database Structures: rocBLAS and hipBLASLt Analysis

## Executive Summary

rocBLAS and hipBLASLt maintain large kernel database libraries organized by GPU architecture. These are installed in library directories as collections of compiled kernel objects (.co), kernel metadata (.dat), and kernel archives (.hsaco). The databases contain pre-compiled kernels from Tensile and support for extended operations (extop).

## Overall Size Metrics

### hipBLASLt Library Sizes
- **gfx1100**: 42 MB (304 files)
  - 149 .co files
  - 151 .dat files
  - 4 .hsaco files
  
- **gfx1201**: 320 MB (590 files)
  - Proportionally larger due to more optimization variants

### rocBLAS Library Sizes
- **gfx1100**: 84 MB (439 files)
  - 80 .co files
  - 138 .dat files
  - 220 .hsaco files
  - 1 .txt file
  
- **gfx1201**: 21 MB
  - Smaller than gfx1100 due to targeted optimization

## Installation Directory Structure

### hipBLASLt Kernel Database Location
```
/rocm/<arch>/lib/hipblaslt/library/
  - Kernels.so-000-<arch>.hsaco      [3.7 MB each, arch-specific]
  - hipblasltTransform.hsaco         [1.4 MB, shared]
  - hipblasltExtOpLibrary.dat        [4.3 KB, shared metadata]
  - extop_<arch>.co                  [41 KB each, arch-specific]
  - TensileLibrary_*.co              [100 KB - 250 KB, arch-specific]
  - TensileLibrary_*.dat             [200 KB - 600 KB, arch-specific]
```

Example paths:
- `/home/stella/claude-rocm-workspace/rocm/gfx1100/lib/hipblaslt/library/`
- `/home/stella/claude-rocm-workspace/rocm/gfx1201/lib/hipblaslt/library/`

### rocBLAS Kernel Database Location
```
/rocm/<arch>/lib/rocblas/library/
  - Kernels.so-000-<arch>.hsaco                    [262 KB each]
  - TensileLibrary_lazy_<arch>.dat                 [24 KB each]
  - TensileLibrary_Type_*_fallback_<arch>.hsaco    [160 KB - 590 KB]
  - TensileLibrary_Type_*.co                       [150 KB - 590 KB]
  - TensileLibrary_Type_*.dat                      [24 KB - 610 KB]
```

Example paths:
- `/home/stella/claude-rocm-workspace/rocm/gfx1100/lib/rocblas/library/`
- `/home/stella/claude-rocm-workspace/rocm/gfx1201/lib/rocblas/library/`

## File Format Analysis

### File Type Breakdown

#### 1. HSACO Files (.hsaco)
- **Type**: ELF 64-bit LSB shared object (AMD GPU architecture)
- **Purpose**: Compiled kernel archive containing GPU machine code
- **File Format**: Binary ELF format with AMD GPU metadata
- **Typical Size**: 160 KB - 3.7 MB
- **Example**: `Kernels.so-000-gfx1100.hsaco` (3.7 MB in hipBLASLt)
- **Example**: `TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback_gfx1100.hsaco`

#### 2. CO Files (.co)
- **Type**: ELF 64-bit LSB shared object (AMD GPU architecture)
- **Purpose**: Compiled kernel object for specific operations
- **File Format**: Binary ELF format
- **Typical Size**: 40 KB - 590 KB
- **Example**: `extop_gfx1100.co` (41 KB - extended operations)
- **Example**: `TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.co` (323 KB)

#### 3. DAT Files (.dat)
- **Type**: MessagePack (msgpack) binary format with metadata
- **Purpose**: Kernel metadata/index database
- **File Format**: Binary serialized data structure (not plain text)
- **Typical Size**: 4 KB - 610 KB
- **Content Example**: Hexdump shows:
  ```
  83 a7 67 66 78 31 31 30 30  ..gfx1100
  83 a9 4c 61 79 65 72 4e    ..LayerNorm
  ```
  Indicates architecture (gfx1100), operation names (LayerNorm), function names, I/O types, work item limits, and paths to .co files

### hipblasltExtOpLibrary.dat Structure
- Contains metadata for extended operations (LayerNorm, AMax, Softmax, etc.)
- References architecture-specific .co files
- Format: MessagePack serialized dictionary with operation definitions

## Architecture-Specific Organization

### Supported Architectures

Both libraries organize kernels by GPU architecture with clear naming conventions:

#### hipBLASLt Supported Architectures (in library):
- gfx1100 (RDNA 3)
- gfx1101 (RDNA 3)
- gfx1103 (RDNA 3)

#### rocBLAS Supported Architectures (in library):
- gfx1100 (RDNA 3)
- gfx1101 (RDNA 3)
- gfx1102 (RDNA 3)
- gfx1103 (RDNA 3)

### File Naming Convention

All architecture-specific files follow the pattern:
```
<operation>_<architecture>.ext
TensileLibrary_<type>_<arch>.ext
```

Examples:
- `Kernels.so-000-gfx1100.hsaco` - Kernel archive for gfx1100
- `TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.co`
- `TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1101.dat`

## hipBLASLt Kernel Library Naming

### Core Kernels
- `Kernels.so-000-<gfx>.hsaco` - Main kernel archive
- `hipblasltTransform.hsaco` - Matrix transform kernels (shared across architectures)

### Extended Operations (ExtOp)
- `extop_<gfx>.co` - Extended operation kernels (LayerNorm, Softmax, AMax, etc.)
- `hipblasltExtOpLibrary.dat` - Metadata index for extended operations

### Tensor Contraction Kernels
Naming pattern: `TensileLibrary_<datatype>_<contraction_spec>_<gfx>.<ext>`

Example components:
- `BB_BB_HA` - Data type specifications (bfloat16, bfloat16, half)
- `Bias_Aux_SAV_UA` - Feature flags (bias, auxiliary, scaled alpha/beta, unscaled alpha)
- `Type_BB_HPA` - Precision specification
- `Contraction_l_Ailk_Bjlk_Cijk_Dijk` - Contraction layout specification
  - `Ailk` = Matrix A layout
  - `Bjlk` = Matrix B layout
  - `Cijk` = Matrix C layout
  - `Dijk` = Matrix D (output) layout

Each configuration has:
- `.co` file (compiled kernel) - ~140-250 KB
- `.dat` file (metadata) - ~200-300 KB

## rocBLAS Kernel Library Naming

### Core Kernels
- `Kernels.so-000-<gfx>.hsaco` - Main kernel archive (~262 KB per arch)

### Lazy Loading
- `TensileLibrary_lazy_<gfx>.dat` - Lazy loading metadata (~24 KB per arch)

### Type-Specific Kernels
Pattern: `TensileLibrary_Type_<spec>_<gfx>.<ext>`

Examples with variants:
1. **4xi8I Contraction** (int8 data types)
   - Fallback variants: `_fallback_<gfx>.hsaco`
   - Optimized variants: `_<gfx>.co` and `_<gfx>.dat`
   
2. **BB Contraction** (bfloat16 or similar)
   - Fallback variants: `_fallback_<gfx>.hsaco`
   - Architecture-specific: `_<gfx>.co` and `_<gfx>.dat`
   - File sizes vary: .co (150-600 KB), .dat (230-610 KB)

### Layout Specifications
Similar to hipBLASLt:
- `Ailk_Bjlk_Cijk_Dijk` - Standard row-major contraction
- `Ailk_Bljk_Cijk_Dijk` - Variant with transposed B
- `Alik_Bjlk_Cijk_Dijk` - Variant with different A layout
- `Alik_Bljk_Cijk_Dijk` - Combined layout variant

## Source Tree Organization

### hipBLASLt Kernel Source
```
/develop/therock/rocm-libraries/projects/hipblaslt/library/src/amd_detail/rocblaslt/src/Tensile/Logic/
  asm_full/
    aldebaran/
    gfx1100/
    gfx1201/
    gfx1150/
    gfx1201/
    aquavanjaram/
      gfx942/
      gfx942_20cu/
      gfx942_38cu/
      gfx942_64cu/
      gfx942_80cu/
      gfx942_152cu/
      gfx942_228cu/
    navi31/
    navi32/
    navi33/
    gfx950/
```

Each architecture directory contains:
- GridBased/ - Grid-based kernel implementations
- Equality/ - Equality-based implementations
- Origami/ - Origami optimization variants (gfx950)
- StreamK/ - StreamK implementation (gfx942)

### rocBLAS Kernel Source
```
/develop/therock/rocm-libraries/projects/rocblas/library/src/
  blas1/          - Level 1 BLAS (vector operations)
  blas2/          - Level 2 BLAS (matrix-vector operations)
  blas3/          - Level 3 BLAS (matrix-matrix operations)
    Tensile/
      Logic/      - Architecture-specific kernel logic
  blas_ex/        - Extended precision operations
```

## Database Characteristics

### Key Observations

1. **Architecture Isolation**
   - Each GPU architecture (gfx1100, gfx1101, etc.) has separate .co and .dat files
   - .hsaco files may be combined or separate per architecture
   - Shared files (like hipblasltTransform.hsaco) minimize duplication

2. **Paired Files (.co + .dat)**
   - Most Tensile kernels are paired: `name.co` (kernel code) + `name.dat` (metadata)
   - The .dat file contains configuration and references to the .co file
   - Allows lazy loading and kernel selection at runtime

3. **Scalability**
   - hipBLASLt: 304 files per architecture (42 MB)
   - rocBLAS: 439 files per architecture (84 MB)
   - Multiple architectures mean files multiply: 2 architectures = ~600-800 files total

4. **File Format Consistency**
   - HSACO: Standard ELF format for compiled GPU code
   - CO: ELF format for individual kernel objects
   - DAT: MessagePack serialized configuration format

## Implications for kpack Splitting

### Current State
- Kernel databases are **architecture-specific and cannot be easily shared**
- Installation includes all variants regardless of target architecture
- No runtime filtering for target architecture

### For kpack Splitting Strategy
1. **Separate by Architecture**: Each architecture (gfx1100, gfx1201, etc.) should have separate kernel packages
2. **Handle Paired Files**: When splitting, keep .co and .dat files paired
3. **Shared Files**: Identify genuinely shared files (hipblasltTransform.hsaco) and handle separately
4. **Compression**: With hundreds of similar-sized files, consider archive-based storage to reduce overhead
5. **Metadata Extraction**: Parse .dat files (MessagePack) to understand kernel dependencies and operation mappings

### Size Estimates for Splitting
- Single architecture hipBLASLt: ~14 MB per architecture (42 MB / 3 architectures)
- Single architecture rocBLAS: ~21 MB per architecture (84 MB / 4 architectures)
- Shared overhead: ~1-2 MB per library

## References

### Source Files
- hipBLASLt Library CMakeLists: `/develop/therock/rocm-libraries/projects/hipblaslt/library/`
- rocBLAS Library CMakeLists: `/develop/therock/rocm-libraries/projects/rocblas/library/`
- Tensile Logic: `/develop/therock/rocm-libraries/projects/hipblaslt/library/src/amd_detail/rocblaslt/src/Tensile/Logic/`

### Installed Files
- hipBLASLt: `/home/stella/claude-rocm-workspace/rocm/<gfx>/lib/hipblaslt/library/`
- rocBLAS: `/home/stella/claude-rocm-workspace/rocm/<gfx>/lib/rocblas/library/`

### File Format Details
- HSACO: ELF 64-bit LSB shared object (AMD GPU binary format)
- CO: ELF 64-bit LSB shared object (individual kernel)
- DAT: MessagePack binary serialization format

