---
name: version-commit
description: >-
  Create the release commit of the wagon hitobito_wsjrdp_2027 exactly as
  doc/versioning.md prescribes: bump lib/hitobito_wsjrdp_2027/version.rb on
  main, commit it alone with the `vX.Y.Z <summary>` message and the bullet list
  of every commit since the previous release, then print the tag and push
  commands WITHOUT running them. Use whenever the user asks for a version bump,
  a release commit, a new release/version tag, or types
  /version-commit [patch|minor|major].
---

# Version commit (release commit of the wagon)

Creates the release commit described in `doc/versioning.md` and stops there.
Read that document first; it is the authority on the message format, the tag
and what CI does with a tag push.

## Hard rules

- Never run `git tag`, `git push`, `git pull`, `git commit --amend`, `git reset`
  or anything else that rewrites history or touches the remote. The only
  remote access is one `git fetch`. The only writes are the edit of
  `version.rb`, `git add` of that file and one `git commit`.
- Every precondition below that fails ends the skill with the given error
  message and **no change made**. Do not "fix" a precondition (no checkout of
  main, no pull, no stash) — tell the user what is wrong and stop.
- Never commit anything but `lib/hitobito_wsjrdp_2027/version.rb`.
- Work from the wagon root (the directory containing
  `lib/hitobito_wsjrdp_2027/version.rb`); if that file is not there, stop:
  "Not in the hitobito_wsjrdp_2027 wagon — run this from the wagon repository."

## Usage

```
/version-commit            # asks which number to bump
/version-commit minor      # minor bump, no question (the normal release)
/version-commit patch      # hotfix on top of an existing release
/version-commit major      # era-scale change (has not moved since 2.x)
```

If `version.rb` in the worktree already carries a number different from
`main`, that number is the new version and the argument is ignored (see
step 5).

## Procedure

Run the checks in this order; the first failure stops the skill.

### 1. Branch

`git symbolic-ref --short HEAD` must print `main`. Otherwise stop:
"Not on branch main (currently on `<branch>`). Release commits are made on
main only — switch to main and rerun." Also stop when a rebase, merge or
cherry-pick is in progress (`.git/rebase-merge`, `.git/rebase-apply`,
`MERGE_HEAD` or `CHERRY_PICK_HEAD` exists): "A rebase/merge is in progress —
finish or abort it first."

### 2. Fetch

Run `git fetch origin main --tags`. If it fails, stop: "git fetch origin
failed — cannot verify that main is up to date (offline? authentication?)."
Do not continue with the locally known state.

### 3. Local main == origin/main

`git rev-parse main` and `git rev-parse origin/main` must be identical.
Otherwise report both short SHAs plus `git rev-list --left-right --count
main...origin/main` (ahead/behind) and stop: "Local main and origin/main
differ (main is <n> ahead, <m> behind). Bring them in sync first (`git pull
--ff-only` / push your commits) and rerun." Never pull or push yourself.

### 4. Index

`git diff --cached --name-only` must be empty except for
`lib/hitobito_wsjrdp_2027/version.rb` (a pre-staged bump is fine). Anything
else staged stops the skill: "Other changes are staged (<files>). The release
commit must contain version.rb alone — commit or unstage them first."
Unstaged modifications of other files and untracked files are allowed and
are left untouched.

### 5. Previous and new version

- `MAIN_VERSION`: the number in `git show main:lib/hitobito_wsjrdp_2027/version.rb`.
- `PREV_TAG`: `git describe --tags --abbrev=0 --match 'v*' main`. It must equal
  `v<MAIN_VERSION>`. If not (a bump without a tag, or a tag without a bump),
  do not guess: show both values and ask the user how to proceed — use the
  tag, use `v<MAIN_VERSION>`, or abort.
- `WORKTREE_VERSION`: the number in the worktree copy of `version.rb`.
  - **Different from `MAIN_VERSION`** → this is the new version; do not ask
    for patch/minor/major and ignore any bump argument (tell the user that
    the worktree number is being used). Check plausibility: it must be
    `X.Y.Z` (digits only), greater than `MAIN_VERSION` in semver order, and
    the tag `v<WORKTREE_VERSION>` must not exist (`git tag -l`). If any check
    fails, show the finding and ask the user whether to use the number
    anyway, pick a bump instead, or abort.
  - **Same as `MAIN_VERSION`** → compute the new version from the argument
    (`patch` → X.Y.(Z+1), `minor` → X.(Y+1).0, `major` → (X+1).0.0). Without
    an argument, ask with a question dialog (AskUserQuestion) whose three
    clickable options spell out the resulting numbers; per
    `doc/versioning.md` MINOR is the normal case, PATCH a hotfix on an
    existing release, MAJOR reserved. Put `git log <PREV_TAG>..main --oneline`
    (the doc's basis for picking the number) into the dialog's question text
    itself: text written before a dialog in the same turn is not shown by the
    client, only the dialog is.

`NEW_VERSION` is the result; `NEW_TAG` is `v<NEW_VERSION>`.

### 6. Collect the commits since the previous release

```bash
git log <PREV_TAG>..main --format='%H%x1f%s%x1f%an <%ae>%x1f%(trailers:key=PR,valueonly)%x1f%(trailers:key=Co-authored-by,valueonly)'
```

Newest first, exactly the commits `git log <PREV_TAG>..main --oneline`
lists — drop nothing (the doc: if the list feels absurdly long, release more
often). Per commit:

- **Bullet**: `* <short summary> (#<PR>)`. Shorten the subject aggressively
  (well under 70 characters including the parenthesis), keep the meaning.
- **PR number**: from the `PR:` trailer (`…/pull/<N>`) or a `(#<N>)` in the
  subject. A commit with neither gets a bullet **without** the parenthesis;
  list those commits in a warning above the draft so the user can add the
  number when approving.
- **Co-authors**: collect every `Co-authored-by` trailer value **and** every
  commit author as `Name <email>` (the author of the release commit is not
  excluded). Run every collected identity through `git check-mailmap
  "Name <email>"` first, so `.mailmap` decides the canonical spelling of
  names and addresses; then write each as `Co-authored-by: Name <email>`,
  drop exact duplicates (compare case-insensitively), sort case-insensitively.
  Do not add anyone who is not in the summarized commits.

### 7. Draft the message and get approval

Draft a short release summary from the bullets (one phrase, no trailing
period; compare `git tag -n3` for the house style — it becomes the tag message
and is read by humans in the deploy channel). **The first line
`v<NEW_VERSION> <summary>` must not exceed 72 characters — a hard limit.**
Shorten the summary until it fits, and reject an approval whose edited
summary would break the limit (say why, ask again). Assemble:

```
v<NEW_VERSION> <summary>

* <bullet newest> (#N)
* …
* <bullet oldest> (#N)

Co-authored-by: …
Co-authored-by: …
```

Ask for approval with a question dialog (AskUserQuestion) that carries the
message itself: the complete message as a fenced block **inside the question
text**, preceded by the warning about commits without a PR reference (if
any), and the same message again as the `preview` of the approve option.
Text written before the dialog in the same turn is not shown by the client,
so nothing may be "shown" outside the dialog. Offer two options: approve as
shown, or give changes (summary wording, bullet wording, PR numbers — typed
via "Other"). Apply the changes and ask again the same way until the message
is approved. Nothing is committed before the approval.

### 8. Commit

1. If the worktree `version.rb` does not yet contain `NEW_VERSION`, replace
   the number (only the string inside `VERSION = "…"`).
2. Write the approved message to a temporary file and run

   ```bash
   git add lib/hitobito_wsjrdp_2027/version.rb
   git commit -F <message file> -- lib/hitobito_wsjrdp_2027/version.rb
   ```

3. Verify with `git show --stat HEAD`: exactly one file, the first line is
   `v<NEW_VERSION> <summary>` and at most 72 characters long. Show that
   output.

### 9. Print the tag and push commands — do not run them

The tag message is the summary **without** the version prefix. Print, and
explicitly say that none of these commands has been executed:

```bash
# 1. annotated release tag (not created by the skill)
git tag -a v<NEW_VERSION> -m "<summary>"

# 2. push the commit alone — --no-follow-tags because push.followTags=true
#    in this git config would otherwise push the tag along with main
git push --no-follow-tags origin main

# 3. push the tag — this is the actual release: CI builds app:stable and
#    app:v<NEW_VERSION>, deployments track stable
git push origin v<NEW_VERSION>
```

End with a one-line recap: the new version, the commit SHA, and that tag and
pushes are still to be done by the user.
