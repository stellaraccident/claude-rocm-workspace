# Kernel Database Documentation Index

This directory contains comprehensive documentation about ROCm kernel database structures used by rocBLAS and hipBLASLt, with specific focus on how kernels are organized, stored, and can be split for kpack distribution.

## Documents

### 1. KERNEL-DATABASE-SUMMARY.txt (START HERE)
**Type**: Executive Summary  
**Size**: ~6 KB  
**Best For**: Quick reference, understanding key concepts at a glance

**Contents**:
- Overview and core findings
- Size metrics for hipBLASLt and rocBLAS
- File types and formats (HSACO, CO, DAT)
- Architecture support matrix
- Key properties and implications for kpack splitting
- Practical installation locations

**Read this first** if you're new to the kernel databases or need a quick refresher on the essentials.

### 2. kernel-databases.md (COMPREHENSIVE OVERVIEW)
**Type**: Detailed Technical Document  
**Size**: ~10 KB  
**Best For**: Understanding the complete architecture and organization

**Contents**:
- Overall size metrics for both libraries
- Installation directory structure with examples
- Detailed file format analysis (HSACO, CO, DAT)
- Architecture-specific organization
- File naming conventions and component breakdown
- Source tree organization
- Database characteristics
- Implications for kpack splitting
- Size estimates for splitting scenarios

**Read this** when you need comprehensive understanding of how the databases are structured and organized.

### 3. kernel-databases-technical-reference.md (DEEP DIVE)
**Type**: Technical Reference Manual  
**Size**: ~14 KB  
**Best For**: Implementation details, parsing, and splitting strategy

**Contents**:
- Complete file listing and patterns for both libraries
- File format specifications with hexdump examples
- Architecture-specific variants enumeration
- Kernel naming component breakdown
- Runtime loading and selection mechanisms
- Size and storage implications analysis
- Python code examples for parsing DAT files
- Detailed kpack splitting strategy with package structure
- Dependency chain management
- Optimization opportunities
- Testing and validation procedures
- Programmatic parsing examples

**Read this** when implementing tools, parsing metadata, or planning the actual split.

## Quick Reference

### File Type Summary
| Type | Format | Size | Purpose |
|------|--------|------|---------|
| .hsaco | ELF binary | 160 KB - 3.7 MB | Compiled GPU kernel archive |
| .co | ELF binary | 40 KB - 590 KB | Individual compiled kernel |
| .dat | MessagePack | 4 KB - 610 KB | Metadata/configuration index |

### Size at a Glance
```
hipBLASLt gfx1100:  42 MB  (304 files)
hipBLASLt gfx1201:  320 MB (590 files)
rocBLAS gfx1100:    84 MB  (439 files)
rocBLAS gfx1201:    21 MB
```

### Key Properties
- Kernels are **architecture-specific** - cannot be shared between architectures
- Files are **paired** (.co + .dat) for lazy loading
- **Few shared files** (e.g., hipblasltTransform.hsaco)
- **Clean separation** - no cross-architecture dependencies
- **Compression friendly** - ELF binaries compress 40-50%

### Recommended kpack Splitting
```
rocm-hipblaslt-gfx1100-kernels.kpack  (~14-20 MB)
rocm-hipblaslt-gfx1101-kernels.kpack  (~14-20 MB)
rocm-hipblaslt-gfx1103-kernels.kpack  (~14-20 MB)
rocm-hipblaslt-gfx1201-kernels.kpack  (~150-200 MB)
rocm-hipblaslt-shared.kpack            (~2-3 MB)

rocm-rocblas-gfx1100-kernels.kpack    (~20-30 MB)
rocm-rocblas-gfx1101-kernels.kpack    (~20-30 MB)
rocm-rocblas-gfx1102-kernels.kpack    (~20-30 MB)
rocm-rocblas-gfx1103-kernels.kpack    (~20-30 MB)
```

## Key Findings

### 1. Architecture Isolation is Absolute
Every kernel in the database includes the target architecture in its filename. This enables:
- Perfect separation by architecture
- No shared kernels between architectures
- Clean unpacking of only needed files

### 2. Metadata Format is MessagePack
The .dat files use MessagePack binary serialization. This is:
- Compact and efficient
- Supports lazy loading indicators
- Contains all necessary kernel selection information
- Parseable with standard msgpack libraries

### 3. Size Scaling is Linear
Each additional architecture adds:
- hipBLASLt: ~42 MB per architecture
- rocBLAS: ~84 MB per architecture

But with compression (40-50%), this reduces to:
- hipBLASLt: ~21-25 MB per architecture compressed
- rocBLAS: ~42-50 MB per architecture compressed

### 4. File Pairing is Essential
.co and .dat files MUST stay together:
- Metadata (.dat) references paths to compiled kernels (.co)
- Runtime uses metadata to locate kernel binaries
- Splitting them breaks kernel loading

### 5. Shared Files are Rare
Only identified shared file:
- `hipblasltTransform.hsaco` - used across all architectures
- Everything else is architecture-specific

## Practical Locations

### Installed Libraries (on this system)
```
/home/stella/claude-rocm-workspace/rocm/gfx1100/lib/hipblaslt/library/
/home/stella/claude-rocm-workspace/rocm/gfx1100/lib/rocblas/library/
/home/stella/claude-rocm-workspace/rocm/gfx1201/lib/hipblaslt/library/
/home/stella/claude-rocm-workspace/rocm/gfx1201/lib/rocblas/library/
```

### Source Trees
```
/develop/therock/rocm-libraries/projects/hipblaslt/library/src/amd_detail/rocblaslt/src/Tensile/Logic/
/develop/therock/rocm-libraries/projects/rocblas/library/src/
```

## How to Use These Documents

### For Quick Understanding
1. Read KERNEL-DATABASE-SUMMARY.txt (5 min)
2. Review "Quick Reference" section above

### For Implementation
1. Read KERNEL-DATABASE-SUMMARY.txt (5 min)
2. Read kernel-databases.md (10 min)
3. Review kernel-databases-technical-reference.md section on "Splitting Strategy for kpack"

### For Deep Technical Understanding
1. Read all three documents in order
2. Study file format specifications in technical reference
3. Review Python parsing examples

### For Debugging
1. Check "File Format Specifications" in technical reference
2. Use validation procedures in "Testing and Validation" section
3. Reference "Architecture-Specific Variants" for expected files

## Key Takeaways

1. **Kernel databases are architecture-specific** - no sharing possible
2. **Files come in paired sets** (.co + .dat) - keep together
3. **MessagePack format** for metadata - easily parseable
4. **Linear scaling** with additional architectures
5. **Compression friendly** - ~40-50% reduction possible
6. **Clean separation** enables selective unpacking
7. **Few shared files** - most are architecture-tagged

## Additional Context

These kernel databases are critical for:
- Matrix multiplication operations (GEMM) - Tensile-generated kernels
- Extended operations (LayerNorm, Softmax, AMax)
- Multi-precision support (float, bfloat16, half)
- Architecture-specific optimizations

The kpack splitting strategy aims to:
- Reduce installation size for single-architecture systems
- Enable selective downloading of only needed kernels
- Maintain clean separation and modularity
- Support future architecture additions
