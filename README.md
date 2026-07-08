# lord

Keep a repo's private, unversioned files without committing them.

Every repo accumulates files that belong to it but not in it: `.env`,
`.claude/`, editor state, local overrides. Delete the checkout and they are
gone. lord moves them into a store keyed by the repo's origin URL and
symlinks them back into the worktree. A fresh clone recovers them with one
command.

## How it works

A `.lord` manifest in the repo root lists one literal path per line:

```
# private files, never committed
.env
.claude/
notes.md
```

Running `lord` with no arguments converges the repo to that manifest:

- adopts listed files found in the worktree: each moves into the store and
  leaves a symlink behind
- links store entries missing from the worktree, so a fresh clone gets its
  private files back
- restores files whose line was removed: each moves back into the worktree
  as a real file
- regenerates a fenced block in `.git/info/exclude` so listed paths never
  appear in git status, leaving `.gitignore` alone
- installs pre-commit, post-checkout and post-merge hooks that rerun lord,
  so a staged secret blocks the commit and a checkout that materializes a
  listed file is surfaced immediately
- refuses on conflicts instead of guessing

The manifest itself is managed the same way: it lives in the store and
appears in the worktree as a symlink. A repo with no manifest anywhere gets
one initialized, copied from `$LORD_CONFIG/skel` if that file exists.

With nothing to do it prints nothing and exits 0. The only destructive
operation is the adoption rename.

One caveat: a repo that sets `core.hooksPath`, husky for example, never runs
hooks from `.git/hooks`, so the guards are silent there. Run lord by hand in
those repos or call it from the custom hooks.

## Usage

```
usage: lord [-n] [-e] [-V] [dir]

  -n  dry run: report what a run would do, change nothing
  -e  eject: move every managed file back into the worktree, remove the
      exclude and hook blocks, and delete the repo's store dir if emptied
  -V  print version
```

dir defaults to the current directory and may be anywhere inside the repo.

```
$ printf '.env\n' > .lord
$ lord
adopt .lord
adopt .env
$ ls -l .env
lrwxrwxrwx 1 t t 54 .env -> /home/t/.local/share/lord/github.com/acme/app/.env
```

## Store

Files live under `$LORD_DIR`, default `~/.local/share/lord`, keyed by the
origin URL as `<host>/<owner>/<repo>`. Both ssh and https remotes normalize
to the same key, so reclones and remote rewrites find the same store. A repo
needs an origin remote; it need not exist on the host yet.

The store is plain files, so syncing it between machines is left to tools
that already do that well. Put `~/.local/share/lord` in syncthing, a private
git repo or an rsync job, and every checkout on every machine converges to
the same private files.

Renaming the origin changes the key, so eject before the rename and
reconverge after:

```
$ lord -e
$ git remote set-url origin git@github.com:acme/app2.git
$ lord
```

## Manifest rules

Paths are relative to the repo root and taken literally, no globs. Blank
lines and `#` comments are ignored. A trailing slash is stripped, so
directories may be listed either way. Absolute paths and paths containing
`..` are rejected. A path listed before it exists is excluded at once and
adopted on the run after it appears.

## Conflicts

lord never overwrites data. A path present in both worktree and store, a
symlink pointing somewhere unexpected or a listed path tracked in git each
produce an error naming the path, and the run exits nonzero. Orphaned store
entries and unlisted symlinks into the store produce warnings only.

Errors print as `E<code>: message` with errno-flavored codes:

| code | meaning |
|------|---------|
| 1    | listed path is tracked in git |
| 2    | no origin remote, or store file missing |
| 17   | worktree and store conflict |
| 21   | manifest is not a regular file |
| 22   | invalid flag, manifest entry or directory |

## Environment

| variable | default |
|----------|---------|
| `LORD_DIR` | `$XDG_DATA_HOME/lord`, ie `~/.local/share/lord` |
| `LORD_CONFIG` | `$XDG_CONFIG_HOME/lord`, ie `~/.config/lord` |

`$LORD_CONFIG/skel` seeds the manifest for repos that have none.

## Install

```
make install
```

Installs to `~/.local/bin/lord`. Set `PREFIX` to install elsewhere. lord is
a single POSIX sh script; it needs git, awk and standard utilities.

## Test

```
make check
```

Runs the end-to-end suite: 121 checks across adoption, fresh clones,
conflicts, hooks, eject and dry runs.

## License

MIT
