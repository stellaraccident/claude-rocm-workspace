---
description: Find and address RVW review comments
allowed-tools: Read, Grep, Glob, Edit, Bash(git:*)
---

Find and process all review comments in the working tree.

1. Search for RVW patterns:
   ```
   grep -rn "RVW:" --include="*.py" --include="*.cmake" --include="*.cpp" \
     --include="*.c" --include="*.h" --include="*.hpp" --include="*.toml" \
     --include="*.yaml" --include="*.yml" --include="*.sh" --include="*.md"
   ```

2. For each comment found:
   - Show the context (5 lines before/after)
   - Explain what the feedback is asking
   - Propose a fix
   - After user confirms, implement the fix AND remove the RVW comment

3. After all comments addressed:
   - Show summary of changes
   - Ask: "Stage for another review round?" or "Ready to finalize?"

If staging again, amend the WIP commit. If finalizing, proceed to proper commit.
