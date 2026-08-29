#!/usr/bin/env bash
#
# Set up ruby-lsp for a combined hitobito core + wagon LSP workspace.
# See README.md next to this script for what it does and why.
#
# Safe to re-run: every step checks first and only acts when needed.

set -euo pipefail

WAGON_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)  # …/hitobito_wsjrdp_2027
APP_DIR=$(cd "$WAGON_DIR/.." && pwd)                           # …/development/app
CORE_DIR="$APP_DIR/hitobito"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Run everything with the project's direnv environment (rbenv, GEM_HOME,
# PATH); re-exec through direnv when it is not active yet.
if [ -z "${SETUP_RUBY_LSP_ENV:-}" ] && command -v direnv >/dev/null; then
  export SETUP_RUBY_LSP_ENV=1
  exec direnv exec "$APP_DIR" "${BASH_SOURCE[0]}" "$@"
fi

[ -n "${GEM_HOME:-}" ] || die "GEM_HOME is not set. Is the .envrc allowed? Run: direnv allow"
[ -d "$CORE_DIR" ] || die "hitobito core not found at $CORE_DIR"

# rbenv picks the Ruby version from the *current* directory, and
# `direnv exec DIR' keeps the caller's directory -- so make sure we
# stand in the project before anything resolves `ruby'.
cd "$APP_DIR"

log "Environment"
want_ruby=$(cat "$CORE_DIR/.ruby-version")
have_ruby=$(ruby -e 'print RUBY_VERSION')
[ "$have_ruby" = "$want_ruby" ] ||
  die "ruby $have_ruby is active, but hitobito wants $want_ruby ($(command -v ruby)). Install it, e.g.: rbenv install $want_ruby"
echo "    ruby      $have_ruby"
echo "    GEM_HOME  $GEM_HOME"

log "ruby-lsp gem"
# --conservative keeps an already installed version instead of upgrading
gem install --conservative --no-document ruby-lsp
echo "    $(ruby-lsp --version)"

log "Workspace Gemfile ($APP_DIR/Gemfile)"
# One workspace rooted at app/ needs a Gemfile there. It is a symlink to
# the tracked doc/emacs/Gemfile; app/ itself is fully gitignored.
LINK_TARGET="$(basename "$WAGON_DIR")/doc/emacs/Gemfile"
if [ "$(readlink "$APP_DIR/Gemfile" 2>/dev/null || true)" = "$LINK_TARGET" ]; then
  echo "    symlink already in place"
elif [ -e "$APP_DIR/Gemfile" ] && [ ! -L "$APP_DIR/Gemfile" ]; then
  die "$APP_DIR/Gemfile exists and is not a symlink — move it away first"
else
  ln -sfn "$LINK_TARGET" "$APP_DIR/Gemfile"
  echo "    linked to $LINK_TARGET"
fi

# Start from the wagon's lock so the workspace resolves to the same gem
# versions the containers use, instead of resolving from scratch.
if [ -f "$APP_DIR/Gemfile.lock" ]; then
  echo "    Gemfile.lock already present"
elif [ -f "$WAGON_DIR/Gemfile.lock" ]; then
  cp "$WAGON_DIR/Gemfile.lock" "$APP_DIR/Gemfile.lock"
  echo "    Gemfile.lock seeded from the wagon"
fi

log "bundle install (in $APP_DIR)"
bundle install

log "Local git excludes (.ruby-lsp/)"
# Only relevant when ruby-lsp is also started directly inside core or
# wagon — app/ itself is already gitignored completely.
for repo in "$CORE_DIR" "$WAGON_DIR"; do
  exclude="$(git -C "$repo" rev-parse --absolute-git-dir)/info/exclude"
  if grep -qxF '.ruby-lsp/' "$exclude" 2>/dev/null; then
    echo "    $(basename "$repo"): already excluded"
  else
    echo '.ruby-lsp/' >>"$exclude"
    echo "    $(basename "$repo"): added"
  fi
done

log "Composed bundle + index smoke test (this takes a moment)"
# ruby-lsp builds its own bundle under app/.ruby-lsp on first start;
# --doctor does that and indexes everything once.
ruby-lsp --doctor >/dev/null || die "ruby-lsp --doctor failed"
echo "    ok"

log "Done."
cat <<EOF

One manual step is left, in Emacs: open a Ruby file from core or wagon
and answer the "Import project root" prompt with

    $APP_DIR

See README.md in this directory for the rest.
EOF
