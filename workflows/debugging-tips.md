# Debugging Tips for ROCm Build Infrastructure

## Build System Debugging

### CMake Debug Output

```bash
# Verbose CMake configuration
cmake /path/to/TheRock --debug-output

# Trace CMake execution
cmake /path/to/TheRock --trace

# See all CMake variables
cmake -LAH /path/to/builds/rocm-main
```

### Make/Ninja Verbose Output

```bash
# Make verbose
make VERBOSE=1

# Ninja verbose
ninja -v

# CMake with verbose
cmake --build . --verbose
```

### Compiler Commands

```bash
# Generate compile_commands.json for tooling
cmake /path/to/TheRock -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# View compile commands for specific file
ninja -t commands path/to/file.cpp
```

## Dependency Debugging

### Check Library Dependencies

```bash
# ldd for runtime dependencies
ldd /path/to/binary

# Check ROCm runtime
rocminfo

# Check GPU visibility
rocm-smi
```

### CMake Find Modules

```bash
# Debug find_package
cmake /path/to/TheRock -DCMAKE_FIND_DEBUG_MODE=ON

# Check what CMake found
cmake -LAH | grep -i packagename
```

## Build Failures

### Incremental Build Issues

Sometimes incremental builds get into bad states:

```bash
# Clean build artifacts but keep CMake cache
cmake --build . --target clean

# Nuclear option: full rebuild
rm -rf * && cmake /path/to/TheRock [flags]
```

### Compiler Cache Issues

If using ccache or sccache:

```bash
# Clear ccache
ccache -C

# Check ccache stats
ccache -s
```

## Git/Submodule Issues

### Submodule Problems

```bash
# Check submodule status
git submodule status

# Update submodules
git submodule update --init --recursive

# Clean submodules
git submodule foreach --recursive git clean -xfd
```

### Worktree Issues

```bash
# List worktrees
git worktree list

# Repair worktrees
git worktree repair
```

## Runtime Debugging

### Environment Variables

```bash
# ROCm debugging
export HSA_ENABLE_DEBUG=1
export AMD_LOG_LEVEL=4

# HIP debugging
export HIP_VISIBLE_DEVICES=0
export AMD_SERIALIZE_KERNEL=3
```

### GPU Debugging

```bash
# Check GPU status
rocm-smi

# Monitor GPU usage
watch -n 1 rocm-smi

# Check compute mode
rocminfo | grep -A 5 "Marketing Name"
```

## Performance Debugging

### Build Performance

```bash
# Time the build
time cmake --build . -j$(nproc)

# Ninja build times
ninja -d stats

# Find slow compilation units
ninja -d keeprsp -v 2>&1 | grep "elapsed"
```

### Profiling

[Add profiling tools and techniques specific to ROCm]

## Common Issues

### Issue: "Could not find ROCm"
**Solution:** [Add solution]

### Issue: GPU not visible
**Solution:** Check rocm-smi, verify kernel modules loaded

### Issue: Build hangs
**Solution:** Check for infinite loops in CMake, reduce parallelism

## Tools

- `rocminfo` - System and GPU information
- `rocm-smi` - GPU management and monitoring
- `roctx` - ROCm tracing
- [Add other tools you use]

## Notes

[Add debugging discoveries and tricks here]
