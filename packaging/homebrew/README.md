# Homebrew distribution

The Xi toolchain installs via Homebrew on macOS (Apple Silicon + Intel) and
Linux:

```sh
brew install code-by-sia/xi/xi
xi version
brew upgrade xi        # later, to update
```

`xc`/`xi` are wrappers that point at the bundled `runtime/` and `std/`, so the
only external requirement is a C compiler (`cc` / `clang` / `gcc`) on `PATH` —
`xc` shells out to it to produce native binaries.

## How it's wired

- [`xi.rb`](xi.rb) is the formula. It downloads the per-platform release tarball
  (`xi-v<version>-<target>.tar.gz`), stashes the bundle under `libexec`, and
  writes absolute-path `bin/xc` and `bin/xi` wrappers.
- [`../../scripts/update-formula.sh`](../../scripts/update-formula.sh)
  regenerates `xi.rb` for a version: it fetches the four release tarballs (or
  reads them from a local dir), computes their `sha256`, and rewrites the file.
- The release workflow runs that script after assets are published and pushes
  the refreshed `xi.rb` to the tap repo.

## One-time tap setup

Homebrew resolves `brew install code-by-sia/xi/xi` to the repo
`github.com/code-by-sia/homebrew-xi`, file `Formula/xi.rb`. Create it once:

```sh
# create the tap repo with the current formula
gh repo create code-by-sia/homebrew-xi --public \
  --description "Homebrew tap for the Xi toolchain"
git clone git@github.com:code-by-sia/homebrew-xi.git
mkdir -p homebrew-xi/Formula
cp packaging/homebrew/xi.rb homebrew-xi/Formula/xi.rb
cd homebrew-xi && git add Formula/xi.rb && git commit -m "xi 0.0.67" && git push
```

Then add a repository secret to **this** repo so CI can push formula bumps:

- `HOMEBREW_TAP_TOKEN` — a fine-grained PAT (or deploy token) with
  `contents: write` on `code-by-sia/homebrew-xi`.

After that, every tagged release auto-updates the tap. **The secret is optional**
— even without it the tap never lags: `code-by-sia/homebrew-xi` runs its own
hourly `.github/workflows/sync.yml`, which reads xi's latest release, regenerates
the formula via `scripts/update-formula.sh`, and commits any change (it runs in
the tap repo, so its built-in `GITHUB_TOKEN` is sufficient — no cross-repo token
needed). The secret only makes the bump *immediate* instead of within ~1h. You
can also bump it by hand with `scripts/update-formula.sh <version>` + push.

## Updating the formula manually

```sh
scripts/update-formula.sh 0.0.67       # downloads release tarballs, rewrites xi.rb
# or, from local tarballs:
scripts/update-formula.sh 0.0.67 ./dist
```
