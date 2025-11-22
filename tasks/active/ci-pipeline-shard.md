# Transform from monolithic to sharded TheRock build

**Status:** Not started
**Priority:** P0 (Critical)
**Started:** 2025-11-21
**Target:** 2025-11-24

## Overview

This task is re-implementing the build pipelines in TheRock in support of:

* Multi-stage Sharded Pipeline as described in docs/rfcs/RFC0008-Multi-Arch-Packaging.md
* Improvements to feature/artifact/source topology in the build system itself to better support multi-stage builds in a more declarative way
* Re-working the artifact upload/download to enable proper segmentation of artifacts
* Laying the ground-work for stage level caching (i.e. bootstrap the compiler stage from a prior when none of the sources or build flags have changed).

## Goals

- [ ] Design/implement new build topology metadata to replace/augment the existing `cmake/therock_features.cmake` facility as used by the top-level CMakeLists.txt.
- [ ] Be able to perform a multi-stage build locally
- [ ] Rework build_tools/fetch_sources.py to fetch sources only needed for a given stage
- [ ] Rework build_tools/fetch_artifacts.py to fetch artifacts for a stage's dependents
- [ ] Rework directory structure and build rules so that they function with partial source checkouts
- [ ] Implement "v2" build pipelines which shard the build on Linux
- [ ] Implement "v2" build pipelines which shard the build on Windows

## Design

### Build Topology Metadata System

The core of the sharded pipeline implementation is a centralized, machine-readable topology file that becomes the single source of truth for all build relationships.

#### Key Design Principles

1. **Artifact-Centric Architecture**: Artifacts (not features) are the fundamental build units that cross stage boundaries. The existing `therock_provide_artifact` system is the source of truth - if something doesn't produce an artifact, it can't be built independently or transmitted across stages.

2. **Feature Flags Remain at CMake Level**: THEROCK_ENABLE_* flags continue to exist for conditional compilation within artifacts. They control what goes into artifacts but don't change the topology structure itself.

3. **Artifact Enable Flags**: Each artifact gets its own ENABLE flag (e.g., `THEROCK_ENABLE_ARTIFACT_BLAS`) providing a convenient way to slim builds for specific use cases.

4. **CMake Target Generation**: The system will generate stage-level and artifact-level targets:
   - `ninja stage-compiler` - Build all artifacts in the compiler stage
   - `ninja artifact-core-runtime` - Build only the core-runtime artifact
   - These targets implicitly depend on the underlying subprojects

#### Architecture Overview
- **BUILD_TOPOLOGY.toml** at repository root - Central metadata file defining all 25+ artifacts
- **build_tools/build_topology.py** - Python library for parsing and querying topology
- **Generated CMake files** - Auto-generated from topology, not manually maintained

#### Phase 1: BUILD_TOPOLOGY.toml Structure (Artifact-Centric)

```toml
[metadata]
version = "1.0"

# Stages define build phases - artifacts move between stages
[stages.compiler]
description = "AMD LLVM toolchain and compiler infrastructure"
type = "generic"  # Built once for all architectures
artifacts = ["amd-llvm", "hipify"]
stage_deps = ["third-party"]
source_cone = ["compiler/"]

[stages.runtime]
description = "Core ROCm runtime, HIP, and OpenCL"
type = "generic"
artifacts = ["core-runtime", "core-hip", "core-ocl"]
stage_deps = ["base", "compiler", "third-party"]
source_cone = ["core/"]

[stages.math-libs]
description = "Math libraries (BLAS, FFT, RAND, etc.)"
type = "per-arch"  # Built separately for each GPU architecture
artifacts = ["blas", "fft", "rand", "prim", "rocwmma", "support"]
stage_deps = ["runtime"]
source_cone = ["math-libs/"]

# Artifacts are the fundamental packaging units
[artifacts.amd-llvm]
stage = "compiler"
type = "target-neutral"
descriptor = "artifact-amd-llvm.toml"
components = ["dbg", "dev", "doc", "lib", "run"]
subprojects = ["amd-llvm", "amd-comgr", "hipcc"]
artifact_deps = ["sysdeps"]  # Dependencies on other artifacts

[artifacts.blas]
stage = "math-libs"
type = "target-specific"
descriptor = "artifact-blas.toml"
components = ["dbg", "dev", "doc", "lib", "run", "test"]
subprojects = [
    "rocBLAS", "hipBLAS",      # Core BLAS
    "rocSPARSE", "hipSPARSE",   # Conditional on THEROCK_ENABLE_SPARSE
    "rocSOLVER", "hipSOLVER"    # Conditional on THEROCK_ENABLE_SOLVER
]
artifact_deps = ["core-runtime", "core-hip", "host-blas"]
```

#### Phase 2: Python Helper Library (build_tools/build_topology.py)

Key classes and functionality:
- `BuildTopology` class to parse and validate TOML
- `Stage`, `Feature`, `Artifact`, `Project` dataclasses
- Query methods:
  - `get_stage_projects(stage_name)` - Get all projects for a stage
  - `get_feature_dependencies(feature)` - Get dependency chain
  - `get_artifact_projects(artifact)` - Get projects producing artifact
  - `resolve_stage_dependencies(stage)` - Get all upstream stages
- CMake generation methods:
  - `generate_feature_cmake()` - Create therock_features_generated.cmake
  - `generate_artifact_cmake()` - Create therock_artifacts_generated.cmake
  - `generate_stage_variables()` - Create per-stage project lists

#### Phase 3: CMake Integration

1. **topology_to_cmake.py** - Script to generate CMake includes from BUILD_TOPOLOGY.toml
2. **Modify cmake/therock_features.cmake** - Include generated files, use topology data
3. **Modify cmake/therock_artifacts.cmake** - Include generated files, use topology data
4. **Update top-level CMakeLists.txt** - Add BUILD_TOPOLOGY parsing, support THEROCK_BUILD_STAGE

#### Phase 4: Implementation Strategy

1. Start with minimal BUILD_TOPOLOGY.toml containing just compiler stage
2. Implement basic build_topology.py with core parsing
3. Test CMake generation for single stage
4. Gradually add more stages and features
5. Maintain backward compatibility throughout

#### Key Design Decisions

- **TOML over JSON**: Better readability, comments support, native Python integration
- **Centralized metadata**: Single source of truth eliminates inconsistencies
- **Generated CMake**: Reduces manual maintenance, ensures consistency
- **Dataclass models**: Type safety and validation in Python code
- **Incremental migration**: Can be adopted gradually without breaking existing builds
- **Artifact-based enables**: Replace divergent feature system with artifact-based control

#### Key Insights from Analysis

1. **25 Existing Artifacts**: The codebase already defines 25 distinct artifacts via `therock_provide_artifact`
   - 12 target-neutral (generic) artifacts
   - 13 target-specific (per GPU architecture) artifacts

2. **Artifacts Group Related Projects**: A single artifact often contains multiple related subprojects
   - Example: `blas` artifact contains rocBLAS, hipBLAS, rocSPARSE, hipSPARSE, rocSOLVER, hipSOLVER

3. **Materialized Dependencies**: Each artifact explicitly declares dependencies on other artifacts
   - Enables proper stage boundary enforcement
   - Supports incremental/cached builds between stages

4. **Source Cones**: Each stage defines which directories must be checked out
   - Enables partial source tree checkouts per stage
   - Reduces CI/CD complexity and build times

5. **Component System**: Standard component types (dbg, dev, doc, lib, run, test)
   - Maps directly to package components
   - Enables fine-grained artifact splitting

#### Success Criteria

- All build relationships defined in single BUILD_TOPOLOGY.toml file
- Existing builds continue to work unchanged
- Can filter build by stage using topology metadata
- Python tools can query topology for dependencies
- CMake files are generated, not manually maintained
- Clear separation between stages with well-defined artifact boundaries

## Progress

### Session 1: Initial Design and BUILD_TOPOLOGY.toml (2025-11-21)

#### Completed
1. Created comprehensive BUILD_TOPOLOGY.toml with artifact-centric design
   - Defined all 25 existing artifacts from `therock_provide_artifact` analysis
   - Established 9 initial stages (third-party, base, compiler, runtime, math-libs, ml-libs, comm-libs, profiler, dctools)
   - Added artifact dependency relationships (`artifact_deps`)

2. Refined topology structure based on feedback:
   - Removed unnecessary fields (descriptor, components, subprojects) - these stay in CMakeLists.txt
   - Kept only essential fields: stage, type, artifact_deps, platform (when needed)
   - Recognized that artifacts (not features) are the fundamental packaging boundaries

#### Key Design Decisions Made
- Artifact-centric approach: Artifacts are the real build units
- Feature flags remain at CMake level for conditional compilation within artifacts
- Each artifact will get its own ENABLE flag for build slimming
- CMake will generate stage/artifact targets (e.g., `ninja stage-compiler`, `ninja artifact-blas`)

#### Notes for Next Sessions
1. **Artifact dependencies need review** - Current deps were guessed based on analysis, not explicitly declared before
2. **Source cones need refinement** - Initial definitions are rough
3. **Stage definitions need to be locked down** - Current 9 stages are a starting point

#### Next Major Tasks
1. ~~Lock down stage definitions~~ - COMPLETED
2. Carefully review and correct artifact dependency relationships
3. Refine source cone definitions for partial checkouts
4. Begin implementation of build_topology.py helper library

### Session 2: Stage Refinement (2025-11-21 continued)

#### Completed
1. Implemented three-level hierarchy:
   - **Build Stages** - Pipeline jobs that build sets of artifact groups
   - **Artifact Groups** - Logical groupings of related artifacts
   - **Artifacts** - Individual build outputs (25 existing)

2. Refined build stages to use descriptive names:
   - `foundation` - Critical path (sysdeps, base, core-runtime)
   - `compiler-runtime` - Compiler, runtimes, and profiler-core
   - `math-libs` - Math and ML libraries (per-arch)
   - `comm-libs` - Communication libraries (per-arch, parallel to math-libs)
   - `dctools-core` - Data center tools with minimal deps
   - Future: `dctools-rocm` - DC tools depending on ROCm libraries

3. Key refinements:
   - Split third-party into `third-party-sysdeps` (critical) and `third-party-libs` (optional)
   - Renamed `profiler` → `profiler-core` and moved to compiler-runtime stage
   - Added profiler-core dependencies to math/ML/comm libraries (for annotations)
   - Planned for future dctools split (dctools-core vs dctools-rocm)

#### Design Finalized
- Build stages use descriptive names (not sequential numbers) since they represent graph nodes
- Parallel execution opportunities clearly identified (math-libs || comm-libs)
- Future extensions planned (IREE, profiler-apps, dctools-rocm)

### Session 3: Final Design and Implementation Planning (2025-11-21 continued)

#### Key Design Decisions

1. **Simplified Metadata Approach**:
   - **Removed source_cone fields** - Will checkout everything initially (optimization can be added later)
   - **Architecture details from outside** - Will be injected as JSON into GitHub Actions matrix expansion
   - **Artifact naming is systematic** - Already discoverable via existing libraries using stem
   - **kpack_split deferred** - Easy to add later when needed

2. **What the Topology Contains**:
   - **Build dependency graph** - Complete DAG of artifact dependencies
   - **Three-level hierarchy** - Build stages → Artifact groups → Artifacts
   - **Type indicators** - generic vs per-arch for build planning
   - **Clear artifact ownership** - Each artifact belongs to one artifact group

3. **What the Topology Doesn't Need**:
   - **Source repository mappings** - Check out everything initially
   - **Architecture lists** - Come from CI/CD configuration
   - **Build configuration** - Stays in CMake
   - **S3 paths** - Systematic and computed at runtime

#### Build Stage Operations

Each build stage (1 job for generic, N jobs for per-arch) will:

1. **Checkout sources** - Full checkout initially (no source cone optimization)
2. **Fetch inbound artifacts** - Computed by traversing:
   - Build stage → artifact_groups → artifact_group_deps → all artifacts in those groups
3. **Build** - Using existing CMake with appropriate flags
4. **Split artifacts** (per-arch only) - kpack tool for architecture-specific splitting
5. **Push artifacts** - To S3 using systematic naming

#### Final Topology Structure

```
Build Stages (CI/CD jobs):
├── foundation (sysdeps, base, core-runtime)
├── compiler-runtime (compiler, third-party-libs, hip/opencl runtime, profiler-core)
├── math-libs (math + ML libraries, per-arch)
├── comm-libs (communication libraries, per-arch, parallel to math-libs)
└── dctools-core (minimal DC tools)
    └── Future: dctools-rocm (DC tools needing ROCm libs)

Artifact Groups (25 existing artifacts organized into ~13 groups)
Artifacts (Individual build outputs with explicit dependencies)
```

#### Next Implementation Steps

1. **build_tools/_therock_utils/build_topology.py** - Python library to:
   - Parse BUILD_TOPOLOGY.toml
   - Compute inbound artifact sets for each build stage
   - Generate dependency graphs
   - Validate topology consistency

2. **build_tools/topology_to_cmake.py** - Command-line tool to generate CMake includes:
   - Create artifact-group and build-stage targets
   - Generate THEROCK_ENABLE_ARTIFACT_* flags
   - Integrate with existing therock_features.cmake
   - Uses: `import _therock_utils.build_topology`

3. **build_tools/tests/test_build_topology.py** - Unit tests:
   - Test topology parsing and validation
   - Test dependency computation
   - Test CMake generation
   - Written in unittest style (not pytest)

4. **Future: Pipeline generator** - Create CI/CD workflows:
   - Read build_stages to create job definitions
   - Handle per-arch matrix expansion
   - Manage artifact upload/download between stages

#### Implementation Structure

```
build_tools/
├── _therock_utils/
│   ├── __init__.py
│   └── build_topology.py      # Core topology library
├── topology_to_cmake.py       # CLI tool for CMake generation
├── tests/
│   └── test_build_topology.py # unittest-style tests
└── (existing tools...)
```

#### build_topology.py Design

```python
from dataclasses import dataclass
from typing import List, Dict, Set, Optional
import toml

@dataclass
class BuildStage:
    name: str
    description: str
    artifact_groups: List[str]
    type: str = "generic"  # or "per-arch"

@dataclass
class ArtifactGroup:
    name: str
    description: str
    type: str
    artifact_group_deps: List[str] = field(default_factory=list)

@dataclass
class Artifact:
    name: str
    artifact_group: str
    type: str  # "target-neutral" or "target-specific"
    artifact_deps: List[str] = field(default_factory=list)
    platform: Optional[str] = None  # e.g., "windows"

class BuildTopology:
    def __init__(self, toml_path: str):
        """Load and parse BUILD_TOPOLOGY.toml"""

    def get_build_stages(self) -> List[BuildStage]:
        """Get all build stages"""

    def get_inbound_artifacts(self, build_stage: str) -> Set[str]:
        """Get all artifacts needed by a build stage from previous stages"""
        # This is the key method for CI/CD
        # Traverse: build_stage -> artifact_groups -> artifact_group_deps -> artifacts

    def get_produced_artifacts(self, build_stage: str) -> Set[str]:
        """Get all artifacts produced by a build stage"""

    def validate_topology(self) -> List[str]:
        """Validate topology for cycles, missing references, etc."""

    def get_dependency_graph(self) -> Dict:
        """Generate full dependency graph for visualization"""
```

### Session 4: Implementation Complete (2025-11-21 continued)

#### Implementation Completed

Successfully implemented the build topology system:

1. **build_tools/_therock_utils/build_topology.py** - Core library (318 lines)
   - Parses BUILD_TOPOLOGY.toml
   - Computes inbound/outbound artifact dependencies with transitive resolution
   - Validates topology (cycles, missing references)
   - Generates dependency graphs

2. **build_tools/topology_to_cmake.py** - CLI tool (265 lines)
   - Generates CMake targets for artifacts, artifact groups, and build stages
   - Creates THEROCK_ENABLE_ARTIFACT_* options
   - Outputs build order and dependency variables
   - Supports validation and graph visualization modes

3. **build_tools/tests/test_build_topology.py** - Comprehensive tests (469 lines)
   - 13 unittest-style test cases
   - Tests parsing, validation, dependency resolution
   - All tests passing

#### Validation Results

- BUILD_TOPOLOGY.toml successfully validated
- 5 build stages defined
- 12 artifact groups organized
- 25 artifacts with dependencies mapped
- CMake generation working correctly

#### Key Features Implemented

- **Transitive dependency resolution** - Correctly computes all upstream artifacts needed
- **Cycle detection** - Validates topology for circular dependencies
- **Per-arch support** - Generates architecture-specific targets for per-arch stages
- **Python compatibility** - Supports Python 3.10+ with tomli fallback for older versions

#### Next Steps for CI/CD Integration

1. Include generated CMake in main build system
2. Create GitHub Actions workflows using build stages
3. Implement artifact upload/download scripts using topology
4. Add kpack integration for architecture splitting

### Session 5: CMake Integration Complete (2025-11-21 continued)

#### Completed CMake Integration

Successfully integrated BUILD_TOPOLOGY.toml with TheRock build system:

1. **Modified topology_to_cmake.py**:
   - Removed per-arch loops and ENABLE flags per user requirements
   - Added validation metadata (THEROCK_TOPOLOGY_ARTIFACTS list)
   - Generates targets for artifacts, artifact groups, and build stages

2. **Updated therock_artifacts.cmake**:
   - Added fail-fast validation against topology-defined artifacts
   - Fixed target dependency issue by creating helper targets for file dependencies
   - Correctly integrates with pre-existing targets from topology

3. **Modified CMakeLists.txt**:
   - Added topology generation in block() scope for cleanliness
   - Uses COMMAND_ERROR_IS_FATAL ANY for proper error handling
   - Generates and includes cmake/therock_topology.cmake

4. **Validation Testing**:
   - Tested fail-fast validation with invalid artifact name
   - Verified all targets are properly created (artifacts, groups, stages)
   - Confirmed dependency chains are correctly established

#### Generated Targets

The system now generates:
- **Artifact targets**: `artifact-base`, `artifact-blas`, etc. (25 total)
- **Artifact group targets**: `artifact-group-math-libs`, `artifact-group-compiler`, etc. (12 total)
- **Build stage targets**: `stage-foundation`, `stage-compiler-runtime`, `stage-math-libs`, etc. (5 total)

Example dependency chain:
```
stage-foundation
├── artifact-group-base
│   └── artifact-base
├── artifact-group-core-runtime
│   └── artifact-core-runtime
└── artifact-group-third-party-sysdeps
    └── artifact-sysdeps
```

#### Key Integration Points

- Fail-fast validation prevents undefined artifacts at CMake configure time
- Pre-created targets from topology are properly augmented with file dependencies
- All existing build functionality preserved while adding new organizational structure

#### Ready for CI/CD Pipeline Implementation

The topology system is now fully integrated and ready for:
- GitHub Actions workflow generation based on build stages
- Artifact upload/download between stages
- Per-architecture matrix expansion for math-libs and comm-libs stages
- Stage-level caching and incremental builds

### Session 6: Feature Flag Unification with Topology (2025-11-21 continued)

#### Research Findings on Feature System

Analyzed the existing feature flag system and identified:

1. **18 artifact-level flags** that control entire artifacts (BLAS, MIOPEN, etc.)
2. **3 optional within-artifact flags** (SPARSE, SOLVER within BLAS, MIOPEN_USE_COMPOSABLE_KERNEL)
3. **7 group control flags** (ENABLE_ALL, ENABLE_MATH_LIBS, etc.)
4. **Configuration flags** (MPI, SANITIZER, etc.)

Key observations:
- Features use `therock_add_feature()` with GROUP and REQUIRES parameters
- Dependencies are explicitly declared and transitively resolved
- Platform-specific logic scattered through if() blocks in CMakeLists.txt
- Direct mapping possible between artifacts and most feature flags

#### Feature Unification Plan

**Goal**: Generate THEROCK_ENABLE_* features from artifact topology while preserving user interface.

**Design Decisions**:
1. Use **DISABLE_PLATFORMS** blacklisting (artifacts enabled everywhere by default)
2. Generate features and targets in **single file** (therock_topology_generated.cmake)
3. Add control fields to topology for non-trivial mappings
4. Keep manual features inline in CMakeLists.txt (no separate manual_features.cmake)

**Topology Extensions**:
- `feature_name`: Override default feature name (e.g., "core-hip" → "HIP_RUNTIME")
- `feature_group`: Override default group (e.g., "core-runtime" → "CORE")
- `disable_platforms`: List platforms where artifact unavailable (e.g., ["windows"])

**Default Rules**:
- feature_name: uppercase(artifact_name), replace('-', '_')
- feature_group: uppercase(artifact_group), replace('-', '_')
- disable_platforms: [] (enabled everywhere)

**Implementation Strategy**:
1. Extend therock_add_feature() with DISABLE_PLATFORMS support
2. Add feature generation to topology_to_cmake.py
3. Generate both targets and features in single cmake file
4. Remove ~200 lines of manual feature declarations from CMakeLists.txt
5. Keep group controls and optional sub-features inline

**Benefits**:
- Single source of truth for dependencies
- Platform logic centralized in feature system
- Cleaner CMakeLists.txt
- Automatic validation against topology
- User interface unchanged

### Session 7: Feature Unification Implementation Complete (2025-11-21 continued)

#### Successfully Unified Feature System with Topology

Completed implementation of unified feature flag system that generates THEROCK_ENABLE_* flags from BUILD_TOPOLOGY.toml while preserving the user interface.

**Key Accomplishments**:

1. **Extended BUILD_TOPOLOGY.toml** with feature control fields:
   - `feature_name` - Override default feature name (e.g., "core-hip" → "HIP_RUNTIME")
   - `feature_group` - Override default group mapping (e.g., "core-runtime" → "CORE")
   - `disable_platforms` - Platform blacklist (e.g., ["windows"] for Linux-only)

2. **Enhanced therock_features.cmake** with DISABLE_PLATFORMS support:
   - Platform checking integrated into feature system
   - Automatic OFF default for unsupported platforms
   - Fatal error if user tries to force-enable on unsupported platform

3. **Updated Python infrastructure**:
   - `build_topology.py` parses new fields
   - `topology_to_cmake.py` generates feature declarations in dependency order
   - 21 artifact features auto-generated (25 artifacts - 4 third-party libs)

4. **Cleaned up CMakeLists.txt**:
   - ~200 lines of manual feature declarations moved to if(FALSE) block
   - Group controls and optional sub-features remain inline
   - Generated features loaded from therock_topology.cmake

**Testing Results**:
- Features properly generated with correct dependencies
- Platform restrictions working (Linux-only features properly disabled on Windows)
- User interface unchanged - same -DTHEROCK_ENABLE_* flags work
- Build configuration succeeds (unrelated zlib issue exists but features work)

**Benefits Achieved**:
- Single source of truth for artifact dependencies
- Cleaner CMakeLists.txt without platform-specific if() blocks
- Automatic validation against topology
- Easy to add new artifacts - just update BUILD_TOPOLOGY.toml

The feature unification is complete and ready for use. The system successfully generates features from the topology while maintaining full backward compatibility with the existing user interface.

### Session 8: Comprehensive Testing and Final Cleanup (2025-11-21 continued)

#### Test Plan and Results

Performed comprehensive testing of the unified feature system with the following test scenarios:

**1. All Features Enabled** ✅
- Test: `cmake -DTHEROCK_ENABLE_ALL=ON`
- Result: All 18 artifact features properly enabled with dependencies resolved
- Verified: COMPILER, HIP_RUNTIME, BLAS, MIOPEN, etc. all enabled

**2. Selective Feature Groups** ✅
- Test: `cmake -DTHEROCK_ENABLE_ALL=OFF -DTHEROCK_ENABLE_MATH_LIBS=ON`
- Result: Only math libraries and their dependencies enabled
- Verified: BLAS, FFT, RAND, PRIM, ROCWMMA, SUPPORT enabled; unrelated features OFF

**3. Platform Restrictions** ✅
- Test: Created test CMake script simulating Windows platform with Linux-only feature
- Result: DISABLE_PLATFORMS correctly sets default to OFF on unsupported platforms
- Result: Fatal error when user tries to force-enable on unsupported platform
- Verified: `message(FATAL_ERROR "TEST_LINUX_ONLY is not supported on Windows")`

**4. Invalid Artifact Validation** ✅
- Test: Attempted to define `fake-test-artifact` not in BUILD_TOPOLOGY.toml
- Result: Fail-fast validation caught it immediately
- Error: "Artifact 'fake-test-artifact' is not defined in BUILD_TOPOLOGY.toml"

**5. Dependency Resolution** ✅
- Test: `cmake -DTHEROCK_ENABLE_ALL=OFF -DTHEROCK_ENABLE_MIOPEN=ON`
- Result: All transitive dependencies pulled in automatically
- Verified: BASE, COMPILER, CORE_RUNTIME, HIP_RUNTIME, ROCPROFV3, BLAS, COMPOSABLE_KERNEL enabled

**6. Build Targets Generation** ✅
- Test: Checked ninja targets after configuration
- Result: All targets properly created
  - 5 stage targets: stage-foundation, stage-compiler-runtime, stage-math-libs, stage-comm-libs, stage-dctools-core
  - 48 artifact-related targets (artifacts + expunge variants)
  - Artifact group targets properly created

**7. Reconfigure Triggers** ✅
- Test: Touched BUILD_TOPOLOGY.toml and ran cmake
- Result: Automatic regeneration of therock_topology.cmake
- Verified: CMAKE_CONFIGURE_DEPENDS properly tracks topology files

**8. Feature Group Overrides** ✅
- Fixed during testing: Added `feature_group` overrides for COMPILER→ALL, ROCPROFV3→PROFILER
- Result: Features now properly respect group enables

#### Final Cleanup Completed

- Removed all `if(FALSE)` blocks containing old manual feature definitions (~200 lines)
- Removed transitional comments and notes
- Cleaned up include ordering to ensure features are available when needed
- All temporary test artifacts removed

#### System Validation

The unified feature system is production-ready with:
- **Single source of truth**: BUILD_TOPOLOGY.toml defines all dependencies
- **Backward compatible**: All existing -DTHEROCK_ENABLE_* flags work unchanged
- **Platform aware**: DISABLE_PLATFORMS centralizes platform restrictions
- **Fail-fast**: Invalid artifacts caught at configure time
- **Auto-validation**: Dependencies automatically enforced
- **Clean code**: ~200 lines removed from CMakeLists.txt

Keep progress and design notes updated here so that we can keep working on the task across multiple sessions.
