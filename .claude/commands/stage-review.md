---
description: Stage changes and open VSCode diffs for review
allowed-tools: Bash(git:*), Bash(code:*)
---

Stage current changes for review in VSCode:

1. Check for uncommitted changes with `git status`
2. If there are changes, create a WIP commit:
   ```
   git add -A
   git commit -m "WIP: staged for review"
   ```
3. Get modified files: `git diff --name-only HEAD~1`
4. Open each file's diff in VSCode (current window):
   ```
   code --diff HEAD~1:<file> <file>
   ```
5. Tell the user files are ready for review

Instruct: Add `// RVW:` or `# RVW:` comments inline, then run /process-review
