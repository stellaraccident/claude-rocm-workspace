# kpack Build Integration Plan

## Overview

This document describes the integration of rocm-kpack into TheRock's build pipeline, focusing on a map/reduce architecture for splitting and recombining device code artifacts.

## Problem Statement

TheRock builds produce artifact directories containing mixed host and device code. These need to be:
1. Split into generic (host-only) and architecture-specific (device code) components
2. Recombined according to packaging topology for distribution
3. Organized so runtime can efficiently locate device code

## Architecture

### Key Design Decision: Manifest-Based Indirection

Instead of embedding full kpack search paths in host binaries, we use a two-level indirection:
1. Host binaries contain a relative path to a manifest file
2. The manifest lists available kpack files and their locations
3. The reduce phase updates the manifest without modifying host binaries

This provides flexibility in final assembly while keeping host code architecture-agnostic.

## Map Phase: Per-Build Artifact Splitting

Each architecture build produces artifacts that need splitting. The map phase processes these deterministically.

### Types of Device Code

The map phase handles two distinct types of device code:

1. **Fat Binaries**: Executables and libraries with embedded `.hip_fatbin` sections containing device code for multiple architectures. These need kpack extraction and transformation.

2. **Kernel Databases**: Pre-compiled kernel collections used by libraries like rocBLAS and hipBLASLt, stored as separate files:
   - `.hsaco` files: Compiled GPU kernel archives (160 KB - 3.7 MB each)
   - `.co` files: Individual kernel objects (40 KB - 590 KB each)
   - `.dat` files: MessagePack metadata indexes for lazy loading

   These files are already architecture-specific (e.g., `TensileLibrary_lazy_gfx1100.co`) and just need to be moved to the appropriate architecture artifact while preserving directory structure.

### Input
- Artifact directory from build (e.g., `/develop/therock-build/artifacts/rocblas_lib_gfx110X/`)
- Contains `artifact_manifest.txt` listing prefix directories
- Each prefix contains mixed host and device code

### Process
1. Read `artifact_manifest.txt` to identify prefix directories
2. For each prefix directory:
   - **For fat binaries** (e.g., in `bin/`, `lib/`):
     - Extract device code from `.hip_fatbin` sections
     - Auto-detect ISAs present in the binary
     - Generate one kpack file per ISA
     - Modify host binaries to reference kpack manifest path
   - **For kernel databases** (e.g., `lib/rocblas/library/`, `lib/hipblaslt/library/`):
     - Identify architecture-specific kernel files (.hsaco, .co, .dat)
     - Move to corresponding architecture artifact based on filename suffix
     - Preserve directory structure for database compatibility
3. Create kpack artifact directories following TheRock conventions
4. Generate kpack manifest (`.kpm` file) for this shard

### Output Structure
```
map-output/
├── rocblas_lib_generic/
│   ├── artifact_manifest.txt  # Preserved from input
│   └── {prefix}/
│       ├── .kpack/
│       │   └── rocblas_lib.kpm # Manifest for this component
│       ├── lib/
│       │   ├── librocblas.so  # Modified with .rocm_kpack_manifest marker
│       │   └── rocblas/
│       │       └── library/    # Kernel database directory (now empty)
│       └── bin/
│           └── rocblas-bench  # Modified with .rocm_kpack_manifest marker
├── rocblas_lib_gfx1100/
│   ├── artifact_manifest.txt
│   └── {prefix}/
│       ├── .kpack/
│       │   └── rocblas_lib_gfx1100.kpack  # From fat binaries
│       └── lib/
│           └── rocblas/
│               └── library/
│                   ├── TensileLibrary_lazy_gfx1100.dat
│                   ├── TensileLibrary_lazy_gfx1100.co
│                   └── *.hsaco  # Other gfx1100 kernel files
├── rocblas_lib_gfx1101/
│   ├── artifact_manifest.txt
│   └── {prefix}/
│       ├── .kpack/
│       │   └── rocblas_lib_gfx1101.kpack
│       └── lib/
│           └── rocblas/
│               └── library/
│                   ├── TensileLibrary_lazy_gfx1101.dat
│                   └── TensileLibrary_lazy_gfx1101.co
└── rocblas_lib_gfx1102/
    └── [similar structure]
```

Note: Kernel database files (.hsaco, .co, .dat) are moved to architecture-specific artifacts while preserving their directory structure. Fat binaries have their device code extracted into .kpack files.

### Manifest Format (.kpm)
Using MessagePack format for efficient runtime parsing:
```python
# Conceptual structure (actual format is binary MessagePack)
{
    "version": 1,
    "component": "miopen_lib",
    "kpack_files": [
        {
            "architecture": "gfx1100",
            "filename": "miopen_lib_gfx1100.kpack",  # Always in same .kpack/ directory
            "checksum": b"..."  # SHA256 as bytes
        },
        {
            "architecture": "gfx1101",
            "filename": "miopen_lib_gfx1101.kpack",
            "checksum": b"..."
        }
    ]
}
```

## Reduce Phase: Package Assembly

The reduce phase combines artifacts from all map phases according to packaging topology.

### Input
- Artifact directories from all map phase outputs
- Configuration file defining packaging topology

### Configuration Schema

Architecture grouping is driven by configuration rather than automatic detection. While consecutive architecture numbers often indicate SKU variants within the same IP generation (e.g., gfx1100, gfx1101, gfx1102), there are exceptions and edge cases that make automatic grouping unreliable. The mapping between build topology and packaging topology is therefore explicitly defined in a configuration file.

```yaml
version: 1.0

# Which build provides primary generic artifacts
primary_generic_source: gfx110X

# Architecture grouping for packages
architecture_groups:
  gfx110X:
    display_name: "ROCm gfx110X"
    architectures:
      - gfx1100
      - gfx1101
      - gfx1102

  gfx115X:
    display_name: "ROCm gfx115X"
    architectures:
      - gfx1150
      - gfx1151

# Component-specific overrides
component_overrides:
  rocblas:
    architecture_groups:
      gfx11-unified:
        architectures: [gfx1100, gfx1101, gfx1102, gfx1150, gfx1151]

# Validation rules
validation:
  error_on_duplicate_device_code: true
  verify_generic_artifacts_match: false
```

### Process
1. Download and flatten generic artifacts from primary source
2. Download and flatten kpack artifact directories according to architecture groups
3. Update/merge kpack manifests (`.kpm` files) to reflect complete distribution
4. Organize into package-ready directory structure

### Output Structure
```
package-staging/
├── gfx110X/
│   ├── {flattened-generic-prefixes}/
│   │   ├── .kpack/
│   │   │   ├── miopen_lib.kpm         # Updated manifest for full distribution
│   │   │   ├── miopen_lib_gfx1100.kpack
│   │   │   ├── miopen_lib_gfx1101.kpack
│   │   │   └── miopen_lib_gfx1102.kpack
│   │   └── bin/
│   │       └── binary1                # Still references miopen_lib.kpm
└── gfx115X/
    ├── {flattened-generic-prefixes}/
    │   ├── .kpack/
    │   │   ├── miopen_lib.kpm         # Different manifest for this package
    │   │   ├── miopen_lib_gfx1150.kpack
    │   │   └── miopen_lib_gfx1151.kpack
    │   └── bin/
    │       └── binary1
```

Note: Each build shard remains independently usable - its `.kpm` file references only the kpack files from that shard. The reduce phase creates comprehensive `.kpm` files for the complete distribution.

## Implementation Components

### New Tools

1. **`split_artifacts.py`** - Map phase tool
   - Input: Artifact directory
   - Output: Split generic + per-ISA kpacks
   - Deterministic, no configuration needed

2. **`recombine_artifacts.py`** - Reduce phase tool
   - Input: Multiple artifact directories + config
   - Output: Package-ready directory structure
   - Configuration-driven grouping

### Modified Components

1. **`ElfOffloadKpacker`** - Add manifest reference injection
   - Instead of `.rocm_kpack_ref` with direct kpack paths
   - Inject `.rocm_kpack_manifest` with path to `.kpm` file
   - Path format: `.kpack/{name}_{component}.kpm`

2. **Runtime (future)** - Manifest-aware kpack loading
   - Read manifest path from binary
   - Parse MessagePack manifest
   - Load kpack files from same `.kpack/` directory
   - Handle architecture fallback logic

## Integration with TheRock

### Build Flow
1. Standard TheRock builds produce artifacts (unchanged)
2. Map phase runs per build, splits artifacts
3. CI uploads split artifacts to S3
4. Package jobs download all artifacts
5. Reduce phase combines according to package type
6. Standard packaging tools create DEB/RPM/wheels

### Artifact Naming Convention
Following TheRock's pattern:
- Generic: `{name}_{component}_generic/` (host-only binaries with manifest references)
- Device: `{name}_{component}_gfx{arch}/` (architecture-specific kpack files)
- Manifest: `{name}_{component}.kpm` (always in `.kpack/` directory)

## Advantages of This Approach

1. **Host Code Stability**: Host binaries don't need modification during reduce phase
2. **Flexible Packaging**: Can reorganize kpacks without touching binaries
3. **Deterministic Map**: No configuration needed for splitting
4. **Configurable Reduce**: Packaging topology defined in version-controlled config
5. **Incremental Updates**: Can update manifest without full rebuild

## Open Questions

1. **Manifest Path Resolution**: How should binaries find their `.kpm` file?
   - RESOLVED: Fixed path `.kpack/{name}_{component}.kpm` relative to binary location
   - Need to handle different installation depths (e.g., `/usr/bin/` vs `/usr/lib/rocm/bin/`)

2. **Artifact Tarball Compression**: What compression for kpack artifact tarballs?
   - RESOLVED: Low/no compression since kpack files are already compressed
   - Need to configure in TheRock CI

3. **Validation Strategy**: What checks should reduce phase perform?
   - Required: No duplicate device code per architecture
   - Optional: Verify generic artifacts match across builds
   - Optional: Check kernel compatibility versions

## Next Steps

1. Prototype manifest injection mechanism
2. Test ISA auto-detection with real binaries
3. Design manifest lookup logic for runtime
4. Create example configuration for current build topology
5. Integration test with sample artifacts