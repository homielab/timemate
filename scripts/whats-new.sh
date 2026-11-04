#!/bin/sh
# Prints the bullets of one version from CHANGELOG.md, as a starting point for
# docs/whats-new/{en,vi}.txt (pick the 3-5 changes users notice most, then translate).
# Usage: scripts/whats-new.sh 3.10
set -eu
v=${1:?usage: whats-new.sh <version>}
cd "$(dirname "$0")/.."
awk -v v="$v" '
  /^## / { on = (index($0, "## [" v "]") == 1); next }
  on && /^### / { print ""; print substr($0, 5); next }
  on && /^- / { print "• " substr($0, 3) }
' CHANGELOG.md | sed '1{/^$/d;}'
