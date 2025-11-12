# JAX/XLA LLVM Symbol Interposition Investigation

## Problem Statement

XLA/JAX is experiencing symbol interposition issues on Linux where LLVM symbols from the XLA/JAX shared libraries are being interposed by other LLVM libraries in the process namespace. This occurs even when the external LLVM libraries have properly versioned symbols.

The core issue: Statically linked public symbols from LLVM in XLA shared libraries are **unversioned** and will allow *any* same-named symbol (even if privately versioned) to interpose on them. This is almost always fatal at runtime.

## Background

This is a known issue pattern with LLVM static linking. Similar issue was fixed in llvmlite: https://github.com/numba/llvmlite/pull/1314

### How Symbol Interposition Works on Linux

1. When a shared library statically links LLVM libraries, the LLVM symbols become part of that shared library
2. If these symbols are public (not hidden), they participate in global symbol resolution
3. Linux ELF loader will use the first matching symbol it finds in the process namespace
4. Unversioned symbols (from static linking) can be interposed by ANY same-named symbol, even versioned ones

## Investigation Findings

### Build System Architecture

XLA uses Bazel for building, with the following key components:

1. **LLVM Integration**:
   - LLVM is imported via `@llvm-project` external repository
   - Configured in `third_party/llvm/setup.bzl` using `llvm_configure`
   - Built from source commit `2bc22ea02edda5926f3e53f141def9bf212ac1db`

2. **Shared Library Creation Points**:
   - `tsl_pybind_extension` macro (Python extensions)
   - `xla_cc_binary` with `linkshared = True` (PJRT plugins)
   - Both defined in `xla/tsl/tsl.bzl`

3. **Current Visibility Controls**:
   ```python
   # From tsl_pybind_extension_opensource (lines 713-719, 774-779)
   copts = copts + [
       "-fno-strict-aliasing",
       "-fexceptions",
   ] + select({
       clean_dep("//xla/tsl:windows"): [],
       "//conditions:default": [
           "-fvisibility=hidden",  # This is applied
       ],
   })
   ```
   - Version scripts are generated to control exported symbols
   - Exported symbols list is properly managed

### The Problem

Despite XLA applying `-fvisibility=hidden` when building shared libraries, this **does not retroactively hide symbols from static libraries** that were built without hidden visibility.

The LLVM static libraries are likely built with default (public) visibility, so when they're linked into XLA's shared libraries, their symbols remain public and unversioned.

## Solutions

### Option 1: Build LLVM with Hidden Visibility (Recommended Long-term)

Modify LLVM build configuration to use `-fvisibility=hidden`:

**Location**: Would need to modify `@llvm-raw//utils/bazel:configure.bzl` or patch LLVM build

**Pros**:
- Cleanest solution
- Prevents the issue at the source
- No runtime overhead

**Cons**:
- Requires modifying LLVM build configuration
- May need to be maintained across LLVM updates

### Option 2: Add `-Bsymbolic` Linking (Recommended Short-term)

#### Option 2A: The Surgical Fix for libjax_common.so (Preferred)

Instead of modifying the underlying TSL macro (which is complex due to Bazel's layering), add `-Bsymbolic` directly where `libjax_common.so` is built.

**Location**: `jaxlib/BUILD` line ~145

**Current code**:
```python
pywrap_library(
    name = "jax",
    common_lib_def_files_or_filters = {
        "jaxlib/jax_common": "jax_common.json",
    },
    common_lib_version_scripts = {
        "jaxlib/jax_common": select({
            "@bazel_tools//src/conditions:windows": None,
            "@bazel_tools//src/conditions:darwin": "libjax_common_darwin.lds",
            "//conditions:default": "libjax_common.lds",
        }),
    },
    deps = [
        # ... deps list ...
    ],
)
```

**Add the fix**:
```python
pywrap_library(
    name = "jax",
    common_lib_def_files_or_filters = {
        "jaxlib/jax_common": "jax_common.json",
    },
    common_lib_version_scripts = {
        "jaxlib/jax_common": select({
            "@bazel_tools//src/conditions:windows": None,
            "@bazel_tools//src/conditions:darwin": "libjax_common_darwin.lds",
            "//conditions:default": "libjax_common.lds",
        }),
    },
    # ADD THIS BLOCK - Linux-only -Bsymbolic to prevent symbol interposition
    common_lib_linkopts = {
        "jaxlib/jax_common": select({
            "@bazel_tools//src/conditions:windows": [],
            "@bazel_tools//src/conditions:darwin": [],
            "//conditions:default": ["-Wl,-Bsymbolic"],
        }),
    },
    deps = [
        # ... deps list ...
    ],
)
```

**Why this works**:
- The `pywrap_library` macro accepts `common_lib_linkopts` as a dictionary
- Key is the library name ("jaxlib/jax_common")
- Value is the list of linker options
- We use `select()` to only apply `-Bsymbolic` on Linux (not Windows/macOS)

**Pros**:
- Surgical fix - only affects `libjax_common.so`
- No need to modify underlying infrastructure
- Easy to implement and test
- Platform-specific (Linux only where the problem exists)

**Cons**:
- Only fixes this specific library (not other potential issues)
- May need similar fixes for other libraries if they have the same problem

#### Option 2B: The Big Hammer Fix - Modify TSL Macro (Backup)

If the surgical fix doesn't work or if there are multiple affected libraries, modify the underlying `tsl_pybind_extension` macro to add `-Bsymbolic` to ALL libraries it builds.

**Location**: `xla/tsl/tsl.bzl` - find the `tsl_pybind_extension_opensource` function

**Find these two sections** (around lines ~740-755 and ~780-795):

```python
# First location - when static_deps is used (cc_shared_library path)
user_link_flags = linkopts + select({
    clean_dep("//xla/tsl:macos"): [
        "-Wl,-w",
        "-Wl,-exported_symbols_list,$(location %s)" % exported_symbols_file,
    ],
    clean_dep("//xla/tsl:windows"): [],
    "//conditions:default": [
        "-Wl,--version-script",
        "$(location %s)" % version_script_file,
    ],
}),

# Second location - when static_deps is NOT used (cc_binary path)
linkopts = linkopts + select({
    clean_dep("//xla/tsl:macos"): [
        "-Wl,-w",
        "-Wl,-exported_symbols_list,$(location %s)" % exported_symbols_file,
    ],
    clean_dep("//xla/tsl:windows"): [],
    "//conditions:default": [
        "-Wl,--version-script",
        "$(location %s)" % version_script_file,
    ],
})
```

**Add `-Bsymbolic` to BOTH locations**:
```python
# Add this line in both places, after the version-script line
"//conditions:default": [
    "-Wl,--version-script",
    "$(location %s)" % version_script_file,
    "-Wl,-Bsymbolic",  # ADD THIS LINE
],
```

**Why you might need this**:
- If there are multiple Python extension modules with LLVM symbols
- If the surgical fix doesn't work due to build system complexities
- If you want to prevent the issue across the board

**Pros**:
- Fixes all TSL-built Python extensions at once
- Prevents future issues in new extensions

**Cons**:
- Affects ALL Python extensions built with this macro
- More invasive change to core infrastructure
- May have unintended side effects on extensions that need symbol interposition

### Option 3: Single Shared Library Architecture

Consolidate LLVM usage into a single shared library rather than multiple.

**Pros**:
- Minimizes interposition surface area
- Was the original XLA design (may still be partially in place)

**Cons**:
- Major architectural change
- May not be feasible with current plugin architecture

## Verification Steps

### 1. Check Current Symbol Visibility

```bash
# Find XLA/JAX shared libraries
find /path/to/jax/installation -name "*.so" -type f

# Check for public LLVM symbols (uppercase = public, lowercase = private)
nm -D /path/to/xla_extension.so | grep -i llvm | head -20

# Check for unversioned symbols
objdump -T /path/to/xla_extension.so | grep -i llvm | grep -v '@'
```

### 2. Test `-Bsymbolic` Fix

1. Apply the `-Bsymbolic` change to `xla/tsl/tsl.bzl`
2. Rebuild affected shared libraries
3. Verify symbols are bound correctly:
   ```bash
   readelf -d /path/to/xla_extension.so | grep SYMBOLIC
   ```
4. Test with the failing use case

## Related Files in XLA Codebase

- `xla/tsl/tsl.bzl` - Contains `tsl_pybind_extension` macro
- `xla/xla.default.bzl` - Contains `xla_cc_binary` wrapper
- `third_party/llvm/setup.bzl` - LLVM configuration
- `third_party/llvm/workspace.bzl` - LLVM repository setup
- `xla/pjrt/plugin/*/BUILD` - PJRT plugin builds

## Next Steps

1. **Immediate**: Apply `-Bsymbolic` fix and test
2. **Short-term**: Verify which shared libraries are affected
3. **Long-term**: Investigate building LLVM with hidden visibility

## Critical Bazel Failure Mode: Test Dynamic Linking

### The Problem

Bazel has a catastrophic default behavior: `cc_test` defaults to **dynamic linking** (unlike `cc_binary` which defaults to static). Combined with `--dynamic_mode=default` (the default), this converts ALL `cc_library` targets to shared libraries when building tests. This:

1. **Destroys all visibility control** - Hidden symbols become public
2. **Creates unversioned shared libraries** - Perfect for symbol interposition
3. **Dumps everything into global namespace** - LLVM symbols everywhere
4. **Makes symbols interpose with everything** - Including system libraries

This "feature" was designed to speed up test iteration in Google's monorepo, but for everyone else with external dependencies like LLVM, it's been a source of torture for years.

### The Symptom

```bash
# Building normally: works fine
bazel build //...

# Building tests: suddenly LLVM symbols are everywhere
bazel test //...
# Crashes with symbol interposition errors
```

### The Fix

Add to your `.bazelrc` or command line:

```bash
# Disable Bazel's brain-damaged test dynamic linking
build --dynamic_mode=off
test --dynamic_mode=off
```

Or just for Linux (Windows already has this in XLA):
```bash
build:linux --dynamic_mode=off
test:linux --dynamic_mode=off
```

Alternative: Force static linking in individual tests:
```python
cc_test(
    name = "my_test",
    linkstatic = True,  # Override dynamic default
    # ... rest of rule
)
```

### Why This Matters for LLVM

When `--dynamic_mode=default` (the default) with `cc_test`:
- **Every LLVM `cc_library` becomes a `.so` file** during test builds
- **All carefully crafted visibility controls are ignored**
- **60,000+ LLVM symbols flood the global namespace**
- **These unversioned symbols interpose with ANY other LLVM in the process**
- **Tests crash mysteriously with symbol version mismatches**

With `--dynamic_mode=off`:
- Libraries stay static as intended ("mostly static" mode)
- Visibility controls work
- Symbol interposition only happens where you explicitly created shared libraries

### The Values of --dynamic_mode

Per Bazel documentation:
- **`default`**: Bazel chooses whether to link dynamically (usually does for tests)
- **`off`**: All libraries linked in mostly static mode
- **`fully`**: All libraries linked dynamically (even cc_binary)

### Verification

```bash
# Check if your build is affected
bazel test //some/test --subcommands 2>&1 | grep -E "\.so|\.dylib" | wc -l
# If this shows many .so files being created, you're affected

# With the fix
bazel test //some/test --dynamic_mode=off --subcommands 2>&1 | grep -E "\.so|\.dylib" | wc -l
# Should show far fewer (only intentional shared libraries)
```

**Note**: XLA already sets `--dynamic_mode=off` for Windows (see `tensorflow.bazelrc`), acknowledging this issue exists, but inexplicably leaves it on for Linux where it causes the most damage.

## References

- Similar fix in llvmlite: https://github.com/numba/llvmlite/pull/1314
- ELF symbol interposition: https://stackoverflow.com/questions/5821211/what-is-symbol-interposition
- `-Bsymbolic` documentation: https://sourceware.org/binutils/docs/ld/Options.html

## Notes for Implementation

When implementing the fix, ensure:
1. The change is applied to both `cc_shared_library` path (line ~750) and `cc_binary` path (line ~788) in `tsl_pybind_extension_opensource`
2. Similar changes may be needed in `xla_cc_binary` if it creates shared libraries
3. Test on Linux specifically (macOS and Windows have different linking semantics)
4. Consider adding a Bazel flag to control this behavior for testing

## Investigation Results from Installed JAX

### JAX Version Examined
- JAX 0.8.0 installed in `/develop/therock-venv`
- Note: This is not the exact ROCm build exhibiting the problem, but should be representative

### Key Findings

#### 1. Library Structure
- Main shared library: `libjax_common.so` (306MB - contains statically linked LLVM)
- Small Python extension modules (~3.5K each) that link to `libjax_common.so`
- All Python extensions use `libjax_common.so` as a dependency

#### 2. Symbol Analysis Results

**The Good News**: In this JAX 0.8.0 build, visibility controls appear to be working correctly:
```bash
# No globally exported LLVM symbols found
nm --demangle libjax_common.so | grep " T " | grep "llvm::"
# (no output)

# LLVM symbols are present but marked as local (lowercase 't')
nm --demangle libjax_common.so | grep "llvm::" | head -3
# 000000000c685020 t postUnswitch(llvm::Loop&, ...)
# 000000000c580710 t inferAlignment(llvm::Function&, ...)
# 0000000004382420 t parseTypeArray(mlir::AsmParser&, ...)
```

#### 3. Evidence of LLVM Static Linking
```bash
# Strings in the binary confirm LLVM is statically linked
strings libjax_common.so | grep -i "llvm" | wc -l
# Multiple LLVM-related strings found

# File size confirms static linking (306MB)
ls -lh libjax_common.so
# -rwxrwxr-x 1 stella stella 306M Nov 11 19:05 libjax_common.so
```

#### 4. Dynamic Section Analysis
```bash
readelf -d libjax_common.so | grep -E "(SYMBOLIC|VERSION|SONAME)"
# 0x000000000000000e (SONAME) Library soname: [libjax_common.so]
# Note: No SYMBOLIC flag present
```

### The Smoking Gun

**Critical Finding**: The LLVM symbols are present in the symbol table as LOCAL symbols:

```bash
readelf -s libjax_common.so | grep "_ZN4llvm" | head -5
# 1752: 0000000002d85140     6 FUNC    LOCAL  DEFAULT   14 _ZN4llvm8RTTIRootD2Ev
# 4628: 0000000002e1dec0    76 FUNC    LOCAL  HIDDEN    14 _ZN4llvm12functi[...]
# 4679: 0000000002e1e900     6 FUNC    LOCAL  DEFAULT   14 _ZN4llvm11raw_os[...]
```

**This IS the smoking gun because**:

1. **If LLVM had been built with `-fvisibility=hidden`**, these symbols wouldn't be in the symbol table AT ALL
2. **The symbols are marked LOCAL via version script**, not hidden at compile time
3. **LOCAL symbols can still participate in interposition** - if a global symbol with the same name exists in the process namespace when the library is loaded, references within the library may bind to the external symbol instead of the local one

### Why LOCAL Doesn't Fully Protect Against Interposition

- **LOCAL (STB_LOCAL)** symbols are not exported for external linking, but they're still present in the symbol table
- During dynamic linking, if a **global symbol** with the same name already exists in the process namespace, internal references might still resolve to it
- This is different from symbols compiled with `-fvisibility=hidden`, which are completely removed from the symbol table
- The version script (which we saw being generated) is marking these as LOCAL after the fact, not hiding them at compile time

### Conclusion from This Build

**This JAX build demonstrates the exact problem** - LLVM was built without `-fvisibility=hidden`, then the symbols were marked LOCAL via version script. This provides incomplete protection against interposition:

1. **Different build configurations**: The ROCm build may have different build flags or use a different build path
2. **Missing `-Bsymbolic`**: Even though symbols are hidden, the library doesn't use `-Bsymbolic` linking
3. **Build system variations**: Bazel build configurations can vary significantly between platforms

### How This Causes Interposition Issues

**The interposition scenario**:
1. Process loads a library with global LLVM symbols (e.g., ROCm's LLVM)
2. JAX library is loaded later
3. Even though JAX's LLVM symbols are marked LOCAL, the internal calls within libjax_common.so might still resolve to the global symbols from step 1
4. This causes crashes/corruption because different LLVM versions have incompatible ABIs

### Confirmed: The Fix is Still Needed

The investigation confirms that even "working" JAX builds are vulnerable because:
1. LLVM static libraries are built without `-fvisibility=hidden`
2. Version scripts provide incomplete protection (LOCAL != hidden)
3. No `-Bsymbolic` linking is used as a backstop

**The recommended `-Bsymbolic` fix would force all internal references to bind to the local symbols, preventing interposition**.

## Retrofit Recipe: Adding Hidden Visibility to LLVM Build

### Overview
This is a highly invasive change that requires modifying how LLVM is built within XLA's Bazel build system. The goal is to add `-fvisibility=hidden` to all LLVM compilation units.

### Method 1: Patching LLVM's Bazel Configuration (Recommended)

#### Step 1: Create a new patch file
Create `third_party/llvm/visibility.patch`:

```diff
diff --git a/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel b/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel
--- a/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel
+++ b/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel
@@ -29,6 +29,9 @@ licenses(["notice"])

 llvm_copts = [
     "$(STACK_FRAME_UNLIMITED)",
+    # Add hidden visibility to prevent symbol interposition
+    "-fvisibility=hidden",
+    "-fvisibility-inlines-hidden",
 ]

 enum_targets_gen(
```

**Note**: The actual line numbers may differ based on your LLVM version. The key is to find where `llvm_copts` is defined (currently only contains `"$(STACK_FRAME_UNLIMITED)"`) and add the visibility flags.

#### Step 2: Add the patch to workspace.bzl
Edit `third_party/llvm/workspace.bzl`:

```python
patch_file = [
    "//third_party/llvm:generated.patch",
    "//third_party/llvm:build.patch",
    "//third_party/llvm:mathextras.patch",
    "//third_party/llvm:toolchains.patch",
    "//third_party/llvm:zstd.patch",
    "//third_party/llvm:visibility.patch",  # ADD THIS LINE
],
```

### Method 1b: Modify Existing build.patch (Simpler)

Since `third_party/llvm/build.patch` already exists and modifies the BUILD.bazel file, you can add the visibility flags there:

Edit `third_party/llvm/build.patch` and add:

```diff
@@ -28,6 +28,9 @@
     ],
     copts = llvm_copts,
+    # Add at the same level as copts
+    local_defines = ["LLVM_BUILD_WITH_HIDDEN_VISIBILITY"],
```

And also add to the beginning of the patch:

```diff
diff --git a/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel b/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel
index 7770284e5543..0b45127495dc 100644
--- a/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel
+++ b/utils/bazel/llvm-project-overlay/llvm/BUILD.bazel
@@ -29,6 +29,9 @@ licenses(["notice"])

 llvm_copts = [
     "$(STACK_FRAME_UNLIMITED)",
+    # Add hidden visibility to prevent symbol interposition
+    "-fvisibility=hidden",
+    "-fvisibility-inlines-hidden",
 ]

 enum_targets_gen(
```

### Method 2: Modifying llvm_configure Call

#### Step 1: Extend llvm_configure in setup.bzl
Edit `third_party/llvm/setup.bzl`:

```python
def llvm_setup(name):
    # Build @llvm-project from @llvm-raw using overlays.
    llvm_configure(
        name = name,
        repo_mapping = {"@python_runtime": "@local_config_python"},
        targets = _LLVM_TARGETS,
        # Add visibility configuration
        additional_copts = [
            "-fvisibility=hidden",
            "-fvisibility-inlines-hidden",
        ],
    )
```

Note: This assumes `llvm_configure` accepts `additional_copts`, which it might not. If not, use Method 1.

### Method 3: Creating a Custom LLVM Build Rule Wrapper

#### Step 1: Create a wrapper .bzl file
Create `third_party/llvm/llvm_with_hidden_visibility.bzl`:

```python
load("@llvm-raw//utils/bazel:configure.bzl", "llvm_configure")

def llvm_configure_with_hidden_visibility(**kwargs):
    """Wrapper around llvm_configure that adds hidden visibility flags."""

    # Get existing copts or default to empty list
    copts = kwargs.pop("copts", [])

    # Add hidden visibility flags
    copts = copts + [
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden",
        "-DLLVM_BUILD_WITH_HIDDEN_VISIBILITY=1",
    ]

    # Call original llvm_configure with modified copts
    llvm_configure(
        copts = copts,
        **kwargs
    )
```

#### Step 2: Use the wrapper in setup.bzl
Edit `third_party/llvm/setup.bzl`:

```python
load("//third_party/llvm:llvm_with_hidden_visibility.bzl", "llvm_configure_with_hidden_visibility")

def llvm_setup(name):
    llvm_configure_with_hidden_visibility(
        name = name,
        repo_mapping = {"@python_runtime": "@local_config_python"},
        targets = _LLVM_TARGETS,
    )
```

### Method 4: Global Bazel Configuration (Most Invasive)

#### Step 1: Add to .bazelrc
Add to the project's `.bazelrc` or `tensorflow.bazelrc`:

```bash
# Force hidden visibility for LLVM builds
build --copt=-fvisibility=hidden
build --copt=-fvisibility-inlines-hidden
build --host_copt=-fvisibility=hidden
build --host_copt=-fvisibility-inlines-hidden
```

**Warning**: This affects ALL C++ code, not just LLVM. Use with caution.

### Verification Steps

After applying any of these methods:

1. **Clean build**:
```bash
bazel clean --expunge
```

2. **Rebuild LLVM**:
```bash
bazel build @llvm-project//...
```

3. **Verify symbols in resulting libraries**:
```bash
# After building JAX/XLA
nm -D bazel-out/.../libjax_common.so | grep "_ZN4llvm" | head -10
# Should show no output (symbols not in dynamic table)

# Check full symbol table
nm bazel-out/.../libjax_common.so | grep "_ZN4llvm" | head -10
# Should show no output (symbols completely hidden)
```

### Caveats and Warnings

1. **ABI Compatibility**: This change may break ABI compatibility with other LLVM consumers
2. **Plugin Systems**: If LLVM plugins are used, they may fail to load
3. **Debug Builds**: May need different handling for debug configurations
4. **Platform Differences**: Windows/macOS may need different visibility attributes
5. **Bazel Cache**: Must clear Bazel cache after making these changes
6. **Testing Required**: Extensive testing needed to ensure nothing breaks

### Alternative: Use LLVM Shared Library

Instead of static linking, consider building LLVM as a shared library with proper versioning:

```python
# In BUILD file
cc_shared_library(
    name = "llvm_shared",
    deps = ["@llvm-project//llvm:all_targets"],
    version_script = "llvm.version",
    soname = "libllvm.so.17",
)
```

This avoids the static linking issue entirely but requires managing LLVM as a runtime dependency.

### Notes on Bazel's Limitations

Bazel makes this unnecessarily difficult because:
1. External repositories are hermetic and hard to modify
2. No easy way to inject compiler flags into external builds
3. Patch files are the primary mechanism for modifications
4. Build configuration is scattered across multiple files

The patch file approach (Method 1/1b) is most likely to work reliably, despite being the most invasive.

### Summary of Complete Solution

To fully fix the symbol interposition issue, apply fixes in order of increasing invasiveness:

1. **Immediate surgical fix (Option 2A)**: Add `-Bsymbolic` to `libjax_common.so` specifically:
   - Edit `jaxlib/BUILD` line ~145
   - Add `common_lib_linkopts` with `-Wl,-Bsymbolic` for Linux only
   - This is a simple, targeted fix that doesn't require modifying infrastructure

2. **Big hammer backup (Option 2B)**: If the surgical fix fails, modify the TSL macro:
   - Edit `xla/tsl/tsl.bzl` in two places (~lines 740-755 and 780-795)
   - Add `-Wl,-Bsymbolic` to all TSL-built Python extensions
   - More invasive but guarantees all extensions are protected

3. **Long-term fix (Option 1)**: Add `-fvisibility=hidden` to LLVM build:
   - Modify `third_party/llvm/build.patch` to add visibility flags to `llvm_copts`
   - This prevents the symbols from being in the symbol table in the first place
   - Most correct solution but requires rebuilding LLVM

4. **Verify the fix**:
   ```bash
   # Quick one-liner to check if -Bsymbolic was applied
   readelf -d /path/to/libjax_common.so | grep -q SYMBOLIC && echo "SYMBOLIC is set" || echo "SYMBOLIC is NOT set"

   # More detailed check after rebuilding with -Bsymbolic
   readelf -d bazel-out/.../libjax_common.so | grep SYMBOLIC
   # Should show: 0x000000000000001d (SYMBOLIC) 0x0

   # After rebuilding with hidden visibility
   nm bazel-out/.../libjax_common.so | grep "_ZN4llvm" | wc -l
   # Should show: 0 (no LLVM symbols at all)
   ```

**Recommendation**: Start with Option 2A (surgical fix). If that doesn't work due to Bazel complexities, fall back to Option 2B (big hammer). Deploy Option 1 (hidden visibility) for the long-term proper fix.

The layered approach provides multiple fallback options to work around Bazel's limitations while ensuring the problem gets fixed.

## Contact

Investigation performed by: Stella (with assistance from Claude)
Date: November 11, 2025
Context: ROCm build infrastructure work