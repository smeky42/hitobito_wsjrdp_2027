#!/bin/sh
# Hook the local dev overrides in this directory into the places where Rails
# picks them up, by creating relative symlinks at the original paths.
# Idempotent: correct links are left alone, stale links are fixed, and a real
# file at a target path is an error (move it into this directory first).
# See the "Local dev overrides" section in ../README.md.
set -eu

cd "$(dirname "$0")/.." # wagon root

make_link() {
  source_rel="$1" # relative to the wagon root: dev-only-overrides/<file>
  target_rel="$2" # where Rails expects the file (two directories deep)
  # Relative link body so the link also works inside the Docker bind mount:
  link_body="../../$source_rel"

  if [ ! -e "$source_rel" ]; then
    echo "SKIP  $target_rel (source $source_rel does not exist)"
    return 0
  fi
  if [ -L "$target_rel" ]; then
    if [ "$(readlink "$target_rel")" = "$link_body" ]; then
      echo "OK    $target_rel -> $link_body (already linked)"
      return 0
    fi
    echo "FIX   $target_rel (symlink pointed elsewhere)"
    rm "$target_rel"
  elif [ -e "$target_rel" ]; then
    echo "ERROR $target_rel exists and is a real file, not a symlink." >&2
    echo "      Move it to $source_rel first, then re-run this script." >&2
    exit 1
  fi
  ln -s "$link_body" "$target_rel"
  echo "LINK  $target_rel -> $link_body"
}

make_link dev-only-overrides/local_dev_only_login_bypass.rb config/initializers/local_dev_only_login_bypass.rb
# The polling file watcher is only needed where inotify events do not cross
# the Docker bind mount, i.e. on macOS.
if [ "$(uname -s)" = "Darwin" ]; then
  make_link dev-only-overrides/local_dev_only_file_watcher_macos.rb config/initializers/local_dev_only_file_watcher_macos.rb
else
  echo "SKIP  config/initializers/local_dev_only_file_watcher_macos.rb (not macOS)"
fi
make_link dev-only-overrides/local_db_dump_shim.rake lib/tasks/local_db_dump_shim.rake
