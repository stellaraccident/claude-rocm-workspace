#!/usr/bin/env bash
# Check git status across all ROCm repositories
# Update the REPOS array below with your actual directory paths from directory-map.md

set -e

# Define repositories to check
# Update these paths to match your directory-map.md
declare -a REPOS=(
    "/path/to/TheRock"
    "/path/to/worktree/feature-name"
    "/path/to/HIP"
    # Add more repositories as needed
)

echo "=== ROCm Repository Status Check ==="
echo ""

for repo in "${REPOS[@]}"; do
    if [ ! -d "$repo" ]; then
        echo "⚠️  Repository not found: $repo"
        echo ""
        continue
    fi

    echo "📁 $repo"

    # Check if it's a git repository
    if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir > /dev/null 2>&1; then
        echo "   ⚠️  Not a git repository"
        echo ""
        continue
    fi

    # Get current branch
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "   Branch: $branch"

    # Check for uncommitted changes
    if ! git -C "$repo" diff-index --quiet HEAD -- 2>/dev/null; then
        echo "   ⚠️  Uncommitted changes detected"
    else
        echo "   ✓ Clean working directory"
    fi

    # Check for untracked files
    untracked=$(git -C "$repo" ls-files --others --exclude-standard | wc -l)
    if [ "$untracked" -gt 0 ]; then
        echo "   ⚠️  $untracked untracked file(s)"
    fi

    # Check sync status with remote (if remote exists)
    if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then
        upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name @{u})
        ahead=$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
        behind=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

        if [ "$ahead" -gt 0 ]; then
            echo "   ↑ $ahead commit(s) ahead of $upstream"
        fi
        if [ "$behind" -gt 0 ]; then
            echo "   ↓ $behind commit(s) behind $upstream"
        fi
        if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
            echo "   ✓ In sync with $upstream"
        fi
    else
        echo "   ℹ️  No remote tracking branch"
    fi

    # Check submodules if they exist
    if [ -f "$repo/.gitmodules" ]; then
        submodule_status=$(git -C "$repo" submodule status 2>/dev/null | grep -c "^[+-U]" || echo 0)
        if [ "$submodule_status" -gt 0 ]; then
            echo "   ⚠️  $submodule_status submodule(s) need attention"
        else
            echo "   ✓ Submodules up to date"
        fi
    fi

    echo ""
done

echo "=== Status check complete ==="
