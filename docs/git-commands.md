I'll provide you with the 100 most common Git commands, organized by category for easier reference. These cover the vast majority of daily Git operations:

## Basic Setup & Config
1. `git init` - Initialize a new repository
2. `git clone <url>` - Clone a repository
3. `git config --global user.name "name"` - Set username
4. `git config --global user.email "email"` - Set email
5. `git config --list` - List all configurations
6. `git config --global core.editor "editor"` - Set default editor
7. `git config --global alias.<alias> <command>` - Create command alias

## Basic Operations
8. `git add <file>` - Stage specific file
9. `git add .` - Stage all changes
10. `git add -A` - Stage all changes including deletions
11. `git add -p` - Stage changes interactively
12. `git commit -m "message"` - Commit with message
13. `git commit -am "message"` - Add and commit tracked files
14. `git commit --amend` - Modify last commit
15. `git commit --amend --no-edit` - Amend without changing message

## Status & Information
16. `git status` - Show working tree status
17. `git status -s` - Short status format
18. `git log` - Show commit history
19. `git log --oneline` - Compact log view
20. `git log --graph` - Show branch graph
21. `git log -n <number>` - Show last n commits
22. `git log --author="name"` - Filter by author
23. `git log --since="date"` - Show commits since date
24. `git log --until="date"` - Show commits until date
25. `git log -p` - Show patches with commits
26. `git show <commit>` - Show commit details
27. `git show HEAD` - Show last commit
28. `git diff` - Show unstaged changes
29. `git diff --staged` - Show staged changes
30. `git diff <branch1> <branch2>` - Compare branches
31. `git diff HEAD~1` - Compare with previous commit
32. `git blame <file>` - Show who changed what

## Branching
33. `git branch` - List local branches
34. `git branch -a` - List all branches
35. `git branch -r` - List remote branches
36. `git branch <name>` - Create new branch
37. `git branch -d <name>` - Delete branch (safe)
38. `git branch -D <name>` - Force delete branch
39. `git branch -m <old> <new>` - Rename branch
40. `git checkout <branch>` - Switch branch
41. `git checkout -b <branch>` - Create and switch branch
42. `git switch <branch>` - Switch branch (newer syntax)
43. `git switch -c <branch>` - Create and switch (newer)

## Merging & Rebasing
44. `git merge <branch>` - Merge branch
45. `git merge --no-ff <branch>` - Force merge commit
46. `git merge --abort` - Abort merge
47. `git rebase <branch>` - Rebase onto branch
48. `git rebase -i HEAD~n` - Interactive rebase
49. `git rebase --continue` - Continue after resolving
50. `git rebase --abort` - Abort rebase
51. `git cherry-pick <commit>` - Apply specific commit

## Remote Operations
52. `git remote` - List remotes
53. `git remote -v` - Show remote URLs
54. `git remote add <name> <url>` - Add remote
55. `git remote remove <name>` - Remove remote
56. `git remote rename <old> <new>` - Rename remote
57. `git fetch` - Download remote changes
58. `git fetch --all` - Fetch all remotes
59. `git pull` - Fetch and merge
60. `git pull --rebase` - Fetch and rebase
61. `git push` - Push to remote
62. `git push -u origin <branch>` - Push and set upstream
63. `git push --force` - Force push (dangerous)
64. `git push --force-with-lease` - Safer force push
65. `git push --tags` - Push all tags
66. `git push origin --delete <branch>` - Delete remote branch

## Stashing
67. `git stash` - Stash changes
68. `git stash save "message"` - Stash with message
69. `git stash list` - List stashes
70. `git stash pop` - Apply and remove stash
71. `git stash apply` - Apply stash without removing
72. `git stash drop` - Delete stash
73. `git stash clear` - Delete all stashes
74. `git stash show` - Show stash changes

## Undoing Changes
75. `git reset <file>` - Unstage file
76. `git reset --soft HEAD~1` - Undo commit, keep changes staged
77. `git reset --mixed HEAD~1` - Undo commit, unstage changes
78. `git reset --hard HEAD~1` - Undo commit, discard changes
79. `git reset --hard origin/<branch>` - Reset to remote state
80. `git revert <commit>` - Create reverse commit
81. `git checkout -- <file>` - Discard file changes
82. `git restore <file>` - Restore file (newer syntax)
83. `git restore --staged <file>` - Unstage file (newer)
84. `git clean -fd` - Remove untracked files/directories
85. `git clean -n` - Dry run of clean

## Tags
86. `git tag` - List tags
87. `git tag <name>` - Create lightweight tag
88. `git tag -a <name> -m "message"` - Create annotated tag
89. `git tag -d <name>` - Delete local tag
90. `git push origin <tag>` - Push specific tag
91. `git checkout <tag>` - Checkout tag

## Advanced/Utility
92. `git bisect start` - Start binary search for bug
93. `git bisect good/bad` - Mark commit during bisect
94. `git grep "pattern"` - Search in repository
95. `git reflog` - Show reference log
96. `git ls-files` - List tracked files
97. `git rm <file>` - Remove file from tracking
98. `git rm --cached <file>` - Untrack without deleting
99. `git mv <old> <new>` - Rename/move file
100. `git help <command>` - Get help for command

These commands represent the core Git functionality that developers use regularly. The most frequently used in typical workflows are probably: `add`, `commit`, `push`, `pull`, `status`, `log`, `branch`, `checkout`/`switch`, `merge`, and `diff`.
