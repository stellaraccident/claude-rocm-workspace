#!/usr/bin/env bash
# Quick navigation helper for ROCm directories
# Source this script or create aliases based on it

# Update these paths to match your directory-map.md
export ROCM_THEROCK="/path/to/TheRock"
export ROCM_BUILD_MAIN="/path/to/builds/rocm-main"
export ROCM_BUILD_DEBUG="/path/to/builds/rocm-debug"
export ROCM_WORKTREE_FEATURE="/path/to/worktree/feature-name"
export ROCM_HIP="/path/to/HIP"

# Usage: goto <location>
goto() {
    case "$1" in
        therock|tr)
            cd "$ROCM_THEROCK" || return 1
            ;;
        build|b)
            cd "$ROCM_BUILD_MAIN" || return 1
            ;;
        debug|d)
            cd "$ROCM_BUILD_DEBUG" || return 1
            ;;
        worktree|wt)
            cd "$ROCM_WORKTREE_FEATURE" || return 1
            ;;
        hip)
            cd "$ROCM_HIP" || return 1
            ;;
        workspace|ws)
            cd "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")" || return 1
            ;;
        *)
            echo "Usage: goto <location>"
            echo ""
            echo "Available locations:"
            echo "  therock, tr      - TheRock main repository"
            echo "  build, b         - Main build directory"
            echo "  debug, d         - Debug build directory"
            echo "  worktree, wt     - Feature worktree"
            echo "  hip              - HIP repository"
            echo "  workspace, ws    - This ROCm Claude workspace"
            return 1
            ;;
    esac
    pwd
}

# Create quick aliases
alias rocm-tr="cd $ROCM_THEROCK"
alias rocm-build="cd $ROCM_BUILD_MAIN"
alias rocm-debug="cd $ROCM_BUILD_DEBUG"
alias rocm-ws="cd \$(dirname \$(dirname \$(readlink -f \${BASH_SOURCE[0]})))"

echo "ROCm navigation helpers loaded"
echo "Usage: goto <location>"
echo "Type 'goto' with no arguments to see available locations"
