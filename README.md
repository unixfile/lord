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
operations are the adoption rename and moving a renamed repo's store.

One caveat: a repo that sets `core.hooksPath`, husky for example, never runs
hooks from `.git/hooks`, so the guards are silent there. Run lord by hand in
those repos or call it from the custom hooks.

## Usage

```
usage: lord [-n] [-e] [-i] [-V] [dir]

  -n  dry run: report what a run would do, change nothing
  -e  eject: move every managed file back into the worktree, remove the
      exclude and hook blocks, and delete the repo's store dir if emptied
  -i  identity: print the origin URL, store key, root commit and the
      provider's repo id, looked up now; change nothing
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

A renamed repo keeps its store, see [Renames and transfers](#renames-and-transfers).

## Renames and transfers

Each store holds `.lord-id`, lord's own record, never linked into the
worktree:

```
url git@github.com:acme/app.git
root 5f7e675...
id github github.com 1283757050
```

`root` is the repo's oldest root commit. `id` is the hosting provider's own
repo id, which survives renames and transfers. lord looks it up once, when
it writes the record, so hook runs stay offline. A failed lookup records
`id none`; delete the file to retry.

When the store for the origin URL is missing, lord looks for the store this
repo used before:

- a store carrying the same provider id is the same repo: lord moves it to
  the new key and re-points the links
- without an id, a store this checkout's `.lord` still links into moves too,
  unless its record names another id or another root commit
- a different id means a fork or a copy, which never takes the store
- several stores with the same id stop the run with E17

So a rename is one remote change and one run:

```
$ git remote set-url origin git@github.com:acme/app2.git
$ lord
move github.com/acme/app -> github.com/acme/app2
relink .lord
relink .env
```

A fresh clone under the new name finds the store by id alone. The move
leaves a symlink at the old key, so clones still on the old URL, which the
host keeps redirecting, share the store. If a different repo later answers
at the old URL, told apart by its root commit, lord drops that forward and
gives it a store of its own. A store moved by hand works too: links that
point at a missing path in the store are re-pointed.

`lord -i` prints the URL, key, root commit and the id as looked up now,
next to the recorded one.

### Providers

| provider | hosts | id | token |
|----------|-------|----|-------|
| `github` | github.com | `id` | `GITHUB_TOKEN`, `GH_TOKEN`, else `gh auth token` |
| `gitlab` | gitlab.com | project `id` | `GITLAB_TOKEN` |
| `forgejo`, `gitea` | codeberg.org | `id` | `GITEA_TOKEN`, `FORGEJO_TOKEN` |
| `bitbucket` | bitbucket.org | `uuid` | `BITBUCKET_TOKEN` |
| `bitbucket-dc` | none built in | `id` | `BITBUCKET_TOKEN` |
| `azure` | dev.azure.com, ssh.dev.azure.com | `id` | `AZURE_DEVOPS_PAT` |
| `sourcehut` | git.sr.ht | `rid` | `SRHT_TOKEN`, required even for public repos |

Public repos need no token, except on SourceHut. Tokens reach curl through
its config on stdin, never the command line. Self-hosted instances go in
`$LORD_CONFIG/hosts`, one `<host> <provider> [api-base]` per line:

```
git.example.org gitlab
code.example.org forgejo
github.example.com github https://github.example.com/api/v3
```

Without curl, or for an unknown host, there is no id and only the link rule
applies. `LORD_ID_CMD` replaces the lookup entirely: a command that gets the
origin URL as `$1` and prints `<provider> <host> <id>`, or nothing.

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
| 17   | worktree and store conflict, or several stores with this repo's id |
| 21   | manifest is not a regular file |
| 22   | invalid flag, manifest entry or directory, or a manifest listing `.lord-id` |

## Environment

| variable | default |
|----------|---------|
| `LORD_DIR` | `$XDG_DATA_HOME/lord`, ie `~/.local/share/lord` |
| `LORD_CONFIG` | `$XDG_CONFIG_HOME/lord`, ie `~/.config/lord` |
| `LORD_ID_CMD` | unset: the built-in provider lookups |

`$LORD_CONFIG/skel` seeds the manifest for repos that have none.
`$LORD_CONFIG/hosts` names the provider of self-hosted instances.

## Install

```
make install
```

Installs to `~/.local/bin/lord`. Set `PREFIX` to install elsewhere. lord is
a single POSIX sh script; it needs git, awk and standard utilities, plus
curl for id lookups.

## Test

```
make check
```

Runs the end-to-end suite: 181 checks across adoption, fresh clones,
conflicts, hooks, eject, dry runs, renames and store moves. Id lookups run
offline through `LORD_ID_CMD`.

## License

MIT
