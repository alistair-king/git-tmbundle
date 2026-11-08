# Git worktrees

Choose **Bundles → Git → Worktrees** for:

- **List Worktrees**: a report of branches, checkout directories, commits, and
  current, main, locked, or missing status.
- **Open Worktree…**: select a checkout and open it with TextMate's `mate` tool.
- **Create and Open Worktree…**: create a new branch from HEAD, check out an
  available local branch, or use a branch, tag, or commit for a detached checkout.
  The destination defaults to a sibling of the current checkout.
- **Remove Worktree…**: remove a linked checkout after confirmation, preserving
  its branch. Main, current, locked, and missing checkouts are excluded. Git
  refuses tracked changes and untracked files. Ignored files are removed.

Run commands in a project window or from a saved file in a Git checkout. Both
main and linked checkouts are supported. Worktrees created outside TextMate
appear automatically. Git is found through `TM_GIT` and TextMate's normal
required-command lookup. These commands require macOS's `/usr/bin/ruby`,
TextMate's Bundle Support UI helpers, and a Git version supporting
`worktree list --porcelain -z`; no additional gems are needed.

Creating a checkout copies committed content, without copying unsaved buffers,
uncommitted edits, or installing project dependencies. Before removing a
checkout, save and close its windows and terminals: bundle commands cannot
inspect unsaved buffers or running processes in other windows. Removal never
forces Git and never deletes a branch.

## Testing

Run the isolated integration tests from the bundle repository root:

```sh
/usr/bin/ruby Support/tests/worktrees_test.rb
```

The tests create temporary repositories and cover worktree discovery, new and
existing branches, detached revisions, unusual paths, inherited Git overrides,
cancellation, opening via mate, and protections for dirty or locked checkouts.

## Migrating from the companion bundle

Install this checkout as `Git.tmbundle` in your user bundle directory, which
takes precedence over the managed Git bundle. A symbolic link supports ongoing
development. If this checkout is named `git-tmbundle`, a link named
`Git.tmbundle` gives TextMate the correct bundle extension. Do not overwrite an
existing user Git bundle without preserving any local customizations.

After verifying the Worktrees submenu, remove the separate **Git Worktrees**
companion bundle to avoid duplicate commands. The command UUIDs are preserved.
The native project popup and its branch, grouping, and visibility features
remain part of the TextMate application, independently of these bundle commands.
