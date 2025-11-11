#!/usr/bin/env bash
# Build multiple ROCm configurations in parallel or sequentially
# Update paths below to match your directory-map.md

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build configurations
# Format: "name:build_dir:parallel_jobs"
declare -a BUILD_CONFIGS=(
    "main:/path/to/builds/rocm-main:$(nproc)"
    "debug:/path/to/builds/rocm-debug:$(nproc)"
    # Add more build configs as needed
)

usage() {
    echo "Usage: $0 [OPTIONS] [CONFIG...]"
    echo ""
    echo "Build one or more ROCm configurations"
    echo ""
    echo "Options:"
    echo "  -p, --parallel     Build all configs in parallel (default: sequential)"
    echo "  -c, --clean        Clean before building"
    echo "  -t, --target TARGET  Specify build target (default: all)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Available configs:"
    for config in "${BUILD_CONFIGS[@]}"; do
        name=$(echo "$config" | cut -d: -f1)
        echo "  - $name"
    done
    echo ""
    echo "Examples:"
    echo "  $0 main              # Build main config only"
    echo "  $0 -p main debug     # Build main and debug in parallel"
    echo "  $0 -c main           # Clean and build main"
    echo "  $0 --target install  # Build and install"
}

build_config() {
    local name=$1
    local build_dir=$2
    local jobs=$3
    local clean=$4
    local target=$5

    echo -e "${YELLOW}Building $name configuration...${NC}"

    if [ ! -d "$build_dir" ]; then
        echo -e "${RED}Error: Build directory not found: $build_dir${NC}"
        return 1
    fi

    if [ "$clean" = true ]; then
        echo "Cleaning $name..."
        cmake --build "$build_dir" --target clean || true
    fi

    echo "Building $name with $jobs parallel jobs..."
    if cmake --build "$build_dir" --parallel "$jobs" ${target:+--target "$target"}; then
        echo -e "${GREEN}✓ $name build successful${NC}"
        return 0
    else
        echo -e "${RED}✗ $name build failed${NC}"
        return 1
    fi
}

# Parse arguments
PARALLEL=false
CLEAN=false
TARGET=""
SELECTED_CONFIGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parallel)
            PARALLEL=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            SELECTED_CONFIGS+=("$1")
            shift
            ;;
    esac
done

# If no configs specified, build all
if [ ${#SELECTED_CONFIGS[@]} -eq 0 ]; then
    for config in "${BUILD_CONFIGS[@]}"; do
        name=$(echo "$config" | cut -d: -f1)
        SELECTED_CONFIGS+=("$name")
    done
fi

# Build selected configurations
declare -a PIDS=()
declare -a NAMES=()

for selected in "${SELECTED_CONFIGS[@]}"; do
    found=false
    for config in "${BUILD_CONFIGS[@]}"; do
        name=$(echo "$config" | cut -d: -f1)
        if [ "$name" = "$selected" ]; then
            build_dir=$(echo "$config" | cut -d: -f2)
            jobs=$(echo "$config" | cut -d: -f3)

            if [ "$PARALLEL" = true ]; then
                build_config "$name" "$build_dir" "$jobs" "$CLEAN" "$TARGET" &
                PIDS+=($!)
                NAMES+=("$name")
            else
                if ! build_config "$name" "$build_dir" "$jobs" "$CLEAN" "$TARGET"; then
                    exit 1
                fi
            fi
            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        echo -e "${RED}Error: Unknown config '$selected'${NC}"
        echo "Use -h to see available configs"
        exit 1
    fi
done

# Wait for parallel builds
if [ "$PARALLEL" = true ]; then
    echo ""
    echo "Waiting for parallel builds to complete..."
    failed=false
    for i in "${!PIDS[@]}"; do
        if wait "${PIDS[$i]}"; then
            echo -e "${GREEN}✓ ${NAMES[$i]} completed${NC}"
        else
            echo -e "${RED}✗ ${NAMES[$i]} failed${NC}"
            failed=true
        fi
    done

    if [ "$failed" = true ]; then
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}All builds completed successfully!${NC}"
