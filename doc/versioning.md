# Versioning and Releases

How wagon versions are numbered, how a release commit looks, and how a
release reaches production.

## Where the version lives

`lib/hitobito_wsjrdp_2027/version.rb`:

```ruby
module HitobitoWsjrdp2027
  VERSION = "2.35.0".freeze
end
```

This is the only place the version is stored. The Docker build appends
the short commit SHA to it (`2.35.0-14bc3a5`), so the running instance
always reveals the exact commit it was built from.

## Numbering

`MAJOR.MINOR.PATCH`, applied pragmatically:

* **MINOR** — a regular feature release; the normal case.
* **PATCH** — a hotfix on top of an existing release
  (e.g. `v2.34.1 Fixed wsj_role error`).
* **MAJOR** — reserved for era-scale changes; has not moved since 2.x.

## The release commit

One commit on `main` that contains exactly the version bump in
`version.rb`, with this message format:

* **First line**: `vX.Y.Z <summary>` — the new version number plus a
  short summary of the release. Spend thought on the summary: it
  becomes the tag message and is what humans read in `git tag -n`
  and in the deploy channel.
* **Body**: a markdown bullet list (`*`), one bullet per commit since
  the previous release, newest first (the `git log` order). Keep each
  summary very short (aim for well under 70 characters) and end every
  bullet with the commit's GitHub PR in parentheses, e.g. `(#123)` —
  the number is in the `PR:` trailer of each commit. Collect the raw
  list with:

  ```bash
  git log v<PREVIOUS>..HEAD --oneline
  ```

  Example bullet:

  ```
  * Cost-center and tax-sphere tables with budgets (#154)
  ```

  Shorten each entry aggressively; drop nothing. If the list gets so
  long that this feels absurd, release more often.

## The tag

Releases are marked with an **annotated** tag `vX.Y.Z` on the release
commit. The tag message is the release summary **without** the version
prefix (it is already in the tag name):

```bash
git tag -a v2.35.0 -m "Bookkeeping standing data, typst and other improvements"
```

## What CI does with it

`.github/workflows/docker-build.yml`:

* Every push to `main` builds and pushes the images
  `ghcr.io/<repo>/app:latest` and `web:latest`.
* Pushing a `v*` tag builds `app:stable` + `app:vX.Y.Z` (and the same
  for `web`). **The tag push is the actual release** — deployments
  track `stable`.

## Step by step

1. Make sure `main` is up to date and green:
   `git checkout main && git pull --tags`.
2. Pick the new number (see Numbering) after reviewing
   `git log v<PREVIOUS>..HEAD --oneline`.
3. Edit `lib/hitobito_wsjrdp_2027/version.rb`, stage it — nothing
   else belongs in this commit.
4. Commit with the format above.
5. Tag: `git tag -a vX.Y.Z -m "<summary without version>"`.
6. Push both: `git push origin main vX.Y.Z`.
7. Wait for the Docker build of the tag, then roll out `stable`.
