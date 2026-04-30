# Git Cheat Sheet

## RESET

> Moves HEAD to a target commit. Flag controls how far the reset reaches.
>
> - `--soft`  — HEAD moves, staged + working tree untouched
> - `--mixed` — HEAD moves, staging cleared, working tree untouched *(default)*
> - `--hard`  — HEAD moves, staging cleared, files reset — all changes gone

```
git reset --soft HEAD~1          # undo last commit, keep changes staged
git reset --mixed HEAD~1         # undo last commit, unstage changes (default)
git reset --hard HEAD~1          # undo last commit, discard changes
git reset --hard <commit>        # reset to a specific commit hash
git reset --hard origin/<branch> # reset branch to match remote
```

---

## REVERT

> Creates a new commit that undoes changes — safe for shared/pushed history.

```
git revert <commit>              # undo a commit with a new commit
git revert HEAD                  # undo the last commit
git revert <commit> --no-commit  # stage the revert without committing
```

---

## STASH

```
git stash                        # stash tracked changes
git stash -u                     # stash including untracked files
git stash pop                    # apply latest stash and drop it
git stash list                   # list all stashes
git stash apply stash@{n}        # apply a specific stash, keep it
git stash drop stash@{n}         # delete a specific stash
git stash clear                  # delete all stashes
```

---

## REBASE

```
git rebase main                  # rebase current branch onto main
git rebase -i HEAD~n             # interactive rebase for last n commits
git rebase --continue            # continue after resolving conflicts
git rebase --abort               # cancel rebase, return to previous state
git rebase --skip                # skip current conflicting commit
```

---

## BRANCH

```
git checkout -b <name>           # create and switch to new branch
git switch -c <name>             # create and switch (modern syntax)
git branch -d <name>             # delete merged branch
git branch -D <name>             # force delete branch
git push origin --delete <name>  # delete remote branch
git branch -m <old> <new>        # rename branch
```
