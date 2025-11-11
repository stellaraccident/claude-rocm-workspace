# Build Pipeline Workflows

## Standard Build Workflow

### Initial Configuration

```bash
# Navigate to build directory
cd /path/to/builds/rocm-main

# Configure with CMake
cmake /path/to/TheRock \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/path/to/install \
  [additional flags]

# Build
cmake --build . -j$(nproc)

# Install (optional)
cmake --install .
```

### Incremental Build

```bash
cd /path/to/builds/rocm-main
cmake --build . -j$(nproc)
```

### Clean Build

```bash
cd /path/to/builds/rocm-main
rm -rf *
# Re-run configuration step above
```

## CI Pipeline

### Local CI Testing

[Document how to run CI tests locally]

```bash
# Example commands
```

### Pipeline Stages

1. **Configure Stage**
   - CMake configuration
   - Dependency checking

2. **Build Stage**
   - Parallel compilation
   - Static analysis (if applicable)

3. **Test Stage**
   - Unit tests
   - Integration tests

4. **Package Stage**
   - DEB/RPM generation
   - Docker image creation (if applicable)

## Common Build Configurations

### Debug Build
```bash
cmake /path/to/TheRock \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

### Release with Debug Info
```bash
cmake /path/to/TheRock \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
```

### Specific GPU Architecture
```bash
cmake /path/to/TheRock \
  -DAMDGPU_TARGETS="gfx906;gfx908;gfx90a"
```

## Troubleshooting Builds

### CMake Cache Issues
```bash
# Clear CMake cache
rm CMakeCache.txt
# Or full clean
rm -rf CMakeFiles/ CMakeCache.txt
```

### Dependency Issues
[Document common dependency problems and solutions]

### Build Failures
[Document common build failure patterns and fixes]

## Notes

[Add your build-specific notes and discoveries here]
