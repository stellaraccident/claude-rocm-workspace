# ROCm Claude Code Workspace

This is a dedicated workspace for using Claude Code to work on ROCm/TheRock and related projects.

## Purpose

As a build infrastructure engineer working on ROCm, my workflow involves:
- Multiple source repositories (TheRock, git worktrees, submodules)
- Multiple build directories scattered across the filesystem
- Complex build pipelines and tooling

Rather than making the ROCm project hierarchy itself the Claude Code workspace, this separate meta-repository serves as a "control center" that:
- Provides centralized context and documentation for Claude Code
- Maps out where all the various directories live
- Contains workflows, notes, and helper scripts
- Stays version-controlled without polluting the actual ROCm repositories

## Setup

1. Clone this repository to your preferred location
2. Update `directory-map.md` with your actual directory paths
3. Update `CLAUDE.md` with your project-specific context
4. Run Claude Code from this directory
5. Reference actual ROCm source/build directories using absolute paths

## Usage Pattern

```bash
cd /path/to/rocm-claude-workspace
# Launch Claude Code here
# Claude can read/edit files anywhere via absolute paths
```

## Structure

- `CLAUDE.md` - Overall project context for Claude Code
- `directory-map.md` - Map of all ROCm-related directories on your system
- `ACTIVE-TASKS.md` - Track current and background tasks
- `tasks/` - Task-specific notes and context
  - `tasks/active/` - Currently active tasks
  - `tasks/completed/` - Archived completed tasks
- `workflows/` - Common workflows and procedures
- `scripts/` - Helper scripts for multi-repo operations

## Task Management

This workspace supports juggling multiple tasks simultaneously:

### Starting a New Task

1. Create a new file: `tasks/active/your-task-name.md`
2. Use `tasks/active/example-task.md` as a template
3. Add your task to `ACTIVE-TASKS.md`
4. Switch to the task: Tell Claude "I'm working on your-task-name" or use `/task your-task-name`

### Working with Tasks

- **Switch tasks verbally:** "Let's work on the cmake-refactor task now"
- **Use the slash command:** `/task cmake-refactor`
- **Check active tasks:** Ask Claude to read `ACTIVE-TASKS.md`

### Completing Tasks

```bash
# Move to completed directory
mv tasks/active/task-name.md tasks/completed/

# Update ACTIVE-TASKS.md to remove it from the list
```

### Why This Approach?

- **Single Claude session:** No need to restart when switching tasks
- **Shared context:** Tasks can reference each other when they overlap
- **Organized:** Easy to see what's active vs completed
- **Flexible:** Works for short-term and long-term tasks

## Sharing

Feel free to fork/adapt this setup for your own ROCm work. The directory paths are specific to my environment, so you'll need to update `directory-map.md` for your setup.
