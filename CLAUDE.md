# ROCm Build Infrastructure Project

## Overview

This workspace is for build infrastructure work on ROCm (Radeon Open Compute) via the TheRock repository and related projects.

Project repository: https://github.com/ROCm/TheRock

## Working Environment

**Important:** See `directory-map.md` for all directory locations.

This is a meta-workspace. Actual source and build directories are scattered across the filesystem and referenced by absolute paths.

## Project Context

### What is ROCm?
ROCm is AMD's open-source platform for GPU computing. It includes:
- HIP (Heterogeneous-Interface for Portability) - CUDA alternative
- ROCm runtime and drivers
- Math libraries (rocBLAS, rocFFT, etc.)
- Developer tools and compilers

### Build Infrastructure Focus
As a build infra team member, typical work involves:
- CMake build system configuration
- CI/CD pipeline maintenance
- Build dependency management
- Cross-platform build support
- Build performance optimization
- Package generation and distribution

## Common Tasks

### Building
- Builds typically happen in separate build trees (see directory-map.md)
- Out-of-tree builds are standard practice
- Multiple build configurations (Release, Debug, RelWithDebInfo) often maintained simultaneously

How we build depends on what kind of task we are doing:

#### Developing Build Infra

Good for making changes to the build infra when we aren't expecting to need to do C++ debugging.

1. CMake configure:

```
cmake -B /develop/therock-build -S /develop/therock -GNinja -DTHEROCK_AMDGPU_FAMILIES=gfx1201 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
```

2. Build entire project (very time consuming)

```
cd /develop/therock-build && ninja
```

Configuring the project is often tricky. Rely on me to give you task specific instructions for configuration and incremental builds (or else you will initiate very long build time activities).

#### Working on specific components

Often we have to work on specific subsets of ROCm. We do this with -DTHEROCK_ENABLE_* flags as described in TheRock/README.md. Once the project is configured for the proper subset, it is typical to iterate by expunging and rebuilding a specific named project. Example:

```
cd /develop/therock-build
ninja clr+expunge && ninja clr+dist
```

### Source Navigation
- Source code is across multiple repositories and worktrees
- Git submodules are used extensively
- When editing build configs, check both source tree CMakeLists.txt and build tree caches

### Testing
- Unit tests, integration tests, and packaging tests
- Tests may run on different GPU architectures (gfx906, gfx908, gfx90a, etc.)

## Conventions & Gotchas

### Build System
- [Document your team's CMake conventions]
- [Note any non-standard build flags or requirements]

### Git Workflow

#### Branch Naming
Use the pattern: `users/<username>/<short-description>`

Examples:
- `users/stellaraccident/add-simde-third-party`
- `users/stellaraccident/fix-cmake-detection`

#### Creating a Branch and Committing
```bash
# Create and switch to a new branch
cd /develop/therock
git checkout -b users/stellaraccident/<description>

# Stage changes
git add <files>

# Create commit with structured message and Claude Code footer
git commit -m "$(cat <<'EOF'
<Short summary line>

<Detailed description of what changed and why>

Changes:
- Bullet point list of key changes
- Another change

Additional context or testing notes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Verify commit
git log -1 --stat
```

#### Commit Message Best Practices
- First line: Short summary (50-72 chars)
- Blank line after summary
- Detailed description explaining what and why
- Include "Changes:" section with bullet points for key modifications
- Add testing/verification notes
- Always include the Claude Code footer (emoji + link + Co-Authored-By)

#### Submodules
- Git submodules are used extensively
- When editing build configs, check both source tree and build tree caches

### Tools
- [List common tools: compilers, rocm-cmake, etc.]

## Reference

- [ROCm Documentation](https://rocm.docs.amd.com/)
- [TheRock repository](https://github.com/ROCm/TheRock)
- [Adding Third-Party Dependencies](adding-third-party-dep.md) - Guide for integrating third-party libraries into TheRock
- Internal wiki/docs: [add links]

## Notes

[Add your ongoing notes, discoveries, and context here as you work]
- Note that TheRock is a super-project. The builds under the submodules (like rocm-systems) are sub-projects. Since dependency management is handled by the super-project, you want to refer to those build rules. For example, in the case of ROCR-Runtime and clr, see the `core/CMakeLists.txt` file. This is documented in docs/development/build_system.md.
- Never do `git push` without explicit authorization.
- Do not amend commits without explicit authorization. Stage changes and ask for reviews before commiting.