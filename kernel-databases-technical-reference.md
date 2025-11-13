# Kernel Database Technical Reference: rocBLAS and hipBLASLt

## Complete File Listing and Patterns

### hipBLASLt gfx1100 Library Sample Files

Total: 304 files, 42 MB

#### Category 1: Main Kernels (4 files)
```
-rw-r--r--  1.4M  hipblasltTransform.hsaco      # Shared matrix transform kernels
-rw-r--r--  4.3K  hipblasltExtOpLibrary.dat     # Extended operations metadata
-rw-r--r--  3.7M  Kernels.so-000-gfx1100.hsaco # Architecture-specific kernel archive
-rw-r--r--   41K  extop_gfx1100.co              # Extended operations (LayerNorm, Softmax, AMax)
```

#### Category 2: Tensor Contraction Kernels (300 files, organized by configuration)
Each has a paired .co (compiled) and .dat (metadata) file:

```
# Example family: Type BB HPA Contraction with various parameter layouts
TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.co    [138K]
TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.dat   [201K]

TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Ailk_Bljk_Cijk_Dijk_gfx1100.co    [208K]
TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Ailk_Bljk_Cijk_Dijk_gfx1100.dat   [284K]

TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Alik_Bjlk_Cijk_Dijk_gfx1100.co    [244K]
TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Alik_Bjlk_Cijk_Dijk_gfx1100.dat   [284K]

[... approximately 150 additional pairs with different configurations ...]
```

### rocBLAS gfx1100 Library Sample Files

Total: 439 files, 84 MB

#### Category 1: Core Kernels (4 files)
```
-rw-r--r--  262K  Kernels.so-000-gfx1100.hsaco
-rw-r--r--   24K  TensileLibrary_lazy_gfx1100.dat
-rw-r--r--  42K   TensileLibrary_Type_4xi8I_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback.dat
-rw-r--r--  195K  TensileLibrary_Type_4xi8I_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback_gfx1100.hsaco
```

#### Category 2: Type-Specific Variants with Fallbacks

```
# Int8 Variants
TensileLibrary_Type_4xi8I_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback.dat
TensileLibrary_Type_4xi8I_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback_gfx1100.hsaco [195K]
TensileLibrary_Type_4xi8I_HPA_Contraction_l_Ailk_Bljk_Cijk_Dijk_fallback.dat
TensileLibrary_Type_4xi8I_HPA_Contraction_l_Ailk_Bljk_Cijk_Dijk_fallback_gfx1100.hsaco [163K]

# BFloat16 Variants (no .co files for fallbacks)
TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback.dat
TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback_gfx1100.hsaco [590K]
TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.co              [323K]
TensileLibrary_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.dat             [519K]

[... approximately 100+ additional variants ...]
```

## File Format Specifications

### HSACO Format Details

**File Type**: ELF 64-bit LSB shared object (AMD GPU binary)

Example header analysis:
```
7f 45 4c 46        # ELF magic number
02                 # 64-bit
01                 # Little endian
01                 # System V ABI
```

**Usage**:
- Contains compiled GPU machine code
- Can be loaded directly by HIP runtime
- Multiple HSACO files may be concatenated in some cases
- BuildID included for versioning

**Size Pattern**:
- hipBLASLt kernels: typically 3.7 MB for main kernel archive
- rocBLAS kernels: typically 160 KB - 590 KB for specific implementations
- Fallback implementations: often larger, ~500+ KB

### CO Format Details

**File Type**: ELF 64-bit LSB shared object (AMD GPU architecture specific)

**Usage**:
- Individual compiled kernel objects
- Smaller, more granular than HSACO
- Loaded together with corresponding .dat metadata

**Size Pattern**:
- extop kernels: 40-50 KB
- Contraction kernels: 100-600 KB
- Typically smaller than fallback HSACO files

**Naming Convention**:
```
<operation>_<architecture>.co
```

### DAT Format Details

**File Type**: MessagePack binary serialization

**Hexdump Analysis**:
```
Offset: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
00000: 83 a7 67 66 78 31 31 30 30 83 a9 4c 61 79 65 72
       ^^ - msgpack fixmap (3 entries)
          ^^^^^^^^^^^^^^^^^^ - key: "gfx1100" (7 bytes)
                             ^^^^^^^^^^^^^^^^^ - value: another msgpack object starting with 83 (3 entries)
```

**Content Structure**:
- Top-level keys (examples from hipblasltExtOpLibrary.dat):
  - "gfx1100", "gfx1101", "gfx1103" - per-architecture operation definitions
  
- Per-architecture entries contain:
  - "LayerNorm" - operation name
  - "Softmax", "AMax", "MatrixTransform" - other operations

- Per-operation entries contain:
  - "func_name" - kernel function identifier
  - "io_type" - input/output data type
  - "limit" - work item limits
  - "num_workitems" - work group configuration
  - "co_path" - path to corresponding .co file

**Example Structure**:
```
{
  "gfx1100": {
    "LayerNorm": [
      {
        "func_name": "LayerNorm_DT_S_W_256_C_4_S_1",
        "io_type": "S",
        "limit": 4096,
        "num_workitems": 256,
        "co_path": "extop_gfx1100.co"
      },
      // ... more parameter variants
    ]
  }
}
```

## Architecture-Specific Variants

### hipBLASLt Supported Architectures

Located in `/develop/therock/rocm-libraries/projects/hipblaslt/library/src/amd_detail/rocblaslt/src/Tensile/Logic/asm_full/`:

1. **aldebaran** - CDNA 2 architecture
   - 110CU variant
   - 104CU variant

2. **aquavanjaram** - CDNA 3 architecture
   - gfx942 base
   - gfx942_20cu
   - gfx942_38cu
   - gfx942_64cu
   - gfx942_80cu
   - gfx942_152cu
   - gfx942_228cu

3. **RDNA Series**
   - **gfx1150** - RDNA 2
   - **gfx1200** - RDNA 3
   - **gfx1201** - RDNA 3 variant
   - **gfx1103** - RDNA 3 variant
   - **gfx950** - RDNA 4 (with Origami, StreamK variants)
   - **navi31** - RDNA 3
   - **navi32** - RDNA 3
   - **navi33** - RDNA 3

### rocBLAS Supported Architectures

Same pattern but installed versions typically include:
- gfx1100, gfx1101, gfx1102, gfx1103 (RDNA 3 variants)
- Architecture selection is architecture-specific and cannot be easily shared

## Kernel Naming Component Breakdown

### hipBLASLt Contraction Kernel Names

Pattern:
```
TensileLibrary_<datatype_spec>_<feature_flags>_Type_<precision>_Contraction_l_<memory_layout>_<gfx>.ext
```

Example:
```
TensileLibrary_BB_BB_HA_Bias_Aux_SAV_UA_Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_gfx1100.co
         ^^^^^^ ^^^^^^ ^^ ^^^^ ^^^ ^^^^^ ^^^^^^^ ^^^^^^^^^^^ ^ ^^^^ ^^^^ ^^^^ ^^^^ ^^^^^^^
         Type   In-Out Feature Flags Prec Layout Impl      L layout                 Arch
```

#### Component Meanings:

1. **Input/Output Types**: `BB_BB_HA`
   - First BB: Matrix A input type
   - Second BB: Matrix B input type
   - HA: Half or Auxiliary type for output
   - Possible values: BB (bfloat16), FP (float), HF (half), etc.

2. **Feature Flags**: `Bias_Aux_SAV_UA`
   - `Bias` - Bias addition support
   - `Aux` - Auxiliary buffer support
   - `SAV` - Scaled Alpha Value
   - `UA` - Unscaled Alpha
   - Combined indicate kernel capabilities

3. **Precision Type**: `Type_BB_HPA`
   - BB - bfloat16 type
   - HPA - High Precision Accumulation

4. **Memory Layout**: `l_Ailk_Bjlk_Cijk_Dijk`
   - Format: `l_<MatrixA>_<MatrixB>_<MatrixC>_<MatrixD>`
   - `Ailk` - A uses i,l,k dimensions
   - `Bjlk` - B uses j,l,k dimensions
   - `Cijk` - C uses i,j,k dimensions
   - `Dijk` - D uses i,j,k dimensions
   - Variants: `Bljk` (transposed B), `Alik` (different A layout)

### rocBLAS Type-Specific Naming

More compact pattern:
```
TensileLibrary_Type_<type_code>_<contraction>_<variant_suffix>_<gfx>.ext
```

Examples:
- `Type_4xi8I_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk_fallback` - Int8 with fallback
- `Type_BB_HPA_Contraction_l_Ailk_Bjlk_Cijk_Dijk` - Standard bfloat16 (no fallback suffix = optimized)

## Runtime Loading and Selection

### DAT File Role in Runtime

The .dat files serve as metadata indices:

1. **Architecture Discovery**
   - Runtime reads .dat to identify available architectures
   - Matches against detected GPU architecture

2. **Kernel Selection**
   - For each operation, .dat contains parameter variants
   - Runtime selects appropriate variant based on problem size
   - Example: LayerNorm_DT_S_W_256_C_4 for specific weight/channel dimensions

3. **Path Resolution**
   - .dat specifies which .co file implements each variant
   - Runtime loads corresponding compiled kernel

4. **Lazy Loading**
   - rocBLAS uses "lazy" loading indicated by TensileLibrary_lazy_<gfx>.dat
   - Kernels loaded on-demand rather than all at initialization

### HSACO File Role in Runtime

1. **Fallback Implementation**
   - Used when optimized .co implementation unavailable
   - rocBLAS includes explicit fallback variants with _fallback_ suffix

2. **Comprehensive Kernel Archive**
   - hipBLASLt main Kernels.so file contains broad kernel coverage
   - Supplements specific Tensile libraries

3. **Direct Loading**
   - Can be loaded as complete shared object
   - No metadata file needed (used for certain operations)

## Size and Storage Implications

### Space Usage by Category

#### hipBLASLt gfx1100 Breakdown
```
Kernels.so-000-gfx1100.hsaco    3.7 MB   (9%)
hipblasltTransform.hsaco         1.4 MB   (3%)
Tensile .dat files (151 total)   ~20 MB   (48%)
Tensile .co files (149 total)    ~18 MB   (43%)
Other metadata                   ~2 MB    (5%)
Total:                           42 MB
```

#### rocBLAS gfx1100 Breakdown
```
HSACO files (220 total)          ~75 MB   (89%)
DAT files (138 total)            ~7 MB    (8%)
CO files (80 total)              ~2 MB    (2%)
Lazy loading metadata            ~1 MB    (1%)
Total:                           84 MB
```

### Scaling with Architecture Count

Adding each additional architecture:
- hipBLASLt: +42 MB per architecture
- rocBLAS: +84 MB per architecture

For 5 architectures (gfx1100, 1101, 1102, 1103, 1201):
- hipBLASLt: 210 MB total
- rocBLAS: 420 MB total
- Combined: 630 MB for kernel databases alone

## Parsing DAT Files Programmatically

### Python Example

```python
import msgpack

# Load DAT file
with open('hipblasltExtOpLibrary.dat', 'rb') as f:
    data = msgpack.unpackb(f.read(), raw=False)

# Iterate through architectures
for arch, operations in data.items():
    print(f"Architecture: {arch}")
    for op_name, variants in operations.items():
        print(f"  Operation: {op_name}")
        for variant in variants:
            print(f"    - {variant['func_name']}: {variant['co_path']}")
```

### Key Fields to Extract

From each variant entry:
- `func_name` - Unique kernel identifier
- `io_type` - Data type (S=single, H=half, D=double)
- `limit` - Work item limit
- `num_workitems` - Workgroup size
- `co_path` - Relative path to kernel binary
- `is_scale` - Boolean scale operation support

## Splitting Strategy for kpack

### Architecture-Segregated Splitting

Recommended approach for separate kpack files:

```
rocm-hipblaslt-gfx1100-kernels.kpack
  /lib/hipblaslt/library/
    - Kernels.so-000-gfx1100.hsaco
    - extop_gfx1100.co
    - TensileLibrary_*_gfx1100.co (149 files)
    - TensileLibrary_*_gfx1100.dat (151 files)

rocm-hipblaslt-gfx1101-kernels.kpack
  /lib/hipblaslt/library/
    - Kernels.so-000-gfx1101.hsaco
    - extop_gfx1101.co
    - TensileLibrary_*_gfx1101.co (149 files)
    - TensileLibrary_*_gfx1101.dat (151 files)

rocm-hipblaslt-gfx1103-kernels.kpack
  /lib/hipblaslt/library/
    - (same pattern)

rocm-hipblaslt-shared.kpack
  /lib/hipblaslt/library/
    - hipblasltTransform.hsaco
    - hipblasltExtOpLibrary.dat
```

### Size Reduction for gfx1201

Note: gfx1201 is significantly larger (320 MB vs 42 MB):
- Option 1: Include only gfx1201-specific files (~75 MB)
- Option 2: Use sparse optimization selection
- Option 3: Compress entire library within kpack

### Dependency Chains

When splitting, maintain:
1. .co files paired with corresponding .dat files
2. Architecture markers in filenames enable runtime selection
3. No file dependencies between architectures (clean separation)

## Potential Optimization Opportunities

### 1. Compression Within kpack
Both .co and .hsaco files compress well (ELF format):
- Typical compression ratio: 40-50%
- hipBLASLt gfx1100: 42 MB -> 21-25 MB compressed
- rocBLAS gfx1100: 84 MB -> 42-50 MB compressed

### 2. Archive Format Consolidation
Instead of 300+ individual files:
- Create tar.gz per kernel family
- Extract at installation time
- Reduces filesystem overhead

### 3. Lazy Architecture Detection
- Ship architecture discovery script
- Identify target GPU at installation
- Unpack only necessary architecture

### 4. Shared DAT Consolidation
- hipblasltExtOpLibrary.dat is truly shared
- rocBLAS lazy loading can reference generic fallbacks
- Reduces redundancy in metadata

## Testing and Validation

### File Integrity Checks

```bash
# Verify ELF format
file /lib/hipblaslt/library/Kernels.so-000-gfx1100.hsaco

# Verify msgpack format
python3 -c "import msgpack; msgpack.unpackb(open('file.dat', 'rb').read())"

# Check architecture in filename
ls /lib/hipblaslt/library/ | grep -o 'gfx[0-9]*' | sort -u
```

### Runtime Validation

After unpacking kpack:
1. Check file count matches expected
2. Verify all paired .co/.dat files present
3. Validate HSACO ELF headers
4. Confirm MessagePack .dat files parseable
5. Test kernel loading with HIP runtime

## References

- Installed hipBLASLt library: `/home/stella/claude-rocm-workspace/rocm/gfx1100/lib/hipblaslt/library/` (42 MB, 304 files)
- Installed rocBLAS library: `/home/stella/claude-rocm-workspace/rocm/gfx1100/lib/rocblas/library/` (84 MB, 439 files)
- Source Tensile Logic: `/develop/therock/rocm-libraries/projects/hipblaslt/library/src/amd_detail/rocblaslt/src/Tensile/Logic/`
- MessagePack specification: https://msgpack.org/
- AMD GPU Binary Format (HSACO): ROCm documentation
