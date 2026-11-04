# pub get with many git dependencies

A single Dart package (branch `pub_get_git`) to time `dart pub get` and
`dart pub upgrade` on a large graph of git dependencies: its `pubspec.yaml`
has the same dependencies as the Tekartik "all projects" package, 134 direct
git dependencies resolving to 228 git packages from 77 public GitHub
repositories, plus 149 hosted ones. Nothing is overridden: every git
dependency goes through the pub git source.

## Run

```sh
git clone -b pub_get_git https://github.com/tekartikdev/publicexp pub_get_git
cd pub_get_git
dart pub get   # first run: clones the 77 repositories into the pub cache
dart tool/pub_timing.dart --runs 3 --fetches
```

`tool/pub_timing.dart` uses `dart:io` only, so it runs without resolving the
package. Scenarios, in this order:

| Scenario | Command | Git fetches |
|---|---|---|
| `get-no-lock` | `pubspec.lock` deleted, `dart pub get` | one per repository |
| `upgrade` | `dart pub upgrade` (lock present) | one per repository |
| `get` | `dart pub get`, lock up to date | none |

To compare with a pub built from source, compile it in a pub checkout
(`dart compile kernel bin/pub.dart -o /tmp/pub.dill`) and pass both:

```sh
dart tool/pub_timing.dart --runs 3 --pub "dart pub" --pub "dart /tmp/pub.dill"
```

A pub run from a kernel file starts slower than the SDK one (JIT), so compare
two builds of the same kind. For a cold cache, set `PUB_CACHE` to an empty
directory.

## Results

2026-11-04, Linux, 24 cores, Dart 3.13.7, git 2.53.0, warm pub cache, HTTPS
to GitHub (one `git ls-remote` round trip: about 0.5 s). Median of 3 runs
with `--fetches` (pub `--verbose` adds about 3 s to each command):

| Scenario | `dart pub` (SDK) | pub `fe19066` | pub `fe19066` + prototype |
|---|---|---|---|
| `get-no-lock` | 44.7 s | 56.5 s | 15.6 s |
| `upgrade` | 43.9 s | 51.0 s | 16.1 s |
| `get` | 4.7 s | 4.9 s | 4.7 s |

Each `get-no-lock` and `upgrade` ran 77 `git fetch`, `get` none, in every
column; the lock files produced were the same. pub runs one git command at a
time (`Pool(1)` in `GitSourceCache`): the 77 fetches alone take 39 s one after
the other and 2.8 s 16 at a time. The prototype lets git commands run in
parallel (8 at a time, one at a time per cached repository) and starts the
fetch of each git repository as soon as it is known: all the git packages of
the lock file on `upgrade`, then the git dependencies of each git package
read. What remains is mostly about 1000 short local git commands (`rev-list`,
`show`), still run one after the other by the solver.
