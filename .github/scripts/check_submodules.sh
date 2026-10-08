#!/usr/bin/env bash
# Fail if any submodule is not on the release tag that modules.versions pins.
#
# modules.versions is the source of truth, and a PR that changes a version
# must move the submodule with it, or CI tests the old module and a release
# ships a pointer that disagrees with what modules.versions claims.
#
# The tag's commit is read from the module's remote (ls-remote), because CI
# checks submodules out shallow and without tags.
set -euo pipefail

FAIL=0
while IFS='=' read -r module version; do
  module=$(echo "$module" | xargs)
  version=$(echo "$version" | xargs)
  [ -z "$module" ] && continue
  [[ "$module" == \#* ]] && continue

  key=$(git config -f .gitmodules --get-regexp '^submodule\..*\.url$' \
    | awk -v m="$module" '$2 ~ ("/"m"(\\.git)?$") { sub(/\.url$/, ".path", $1); print $1 }' \
    | head -n1)
  if [ -z "$key" ]; then
    echo "::error::${module} is pinned in modules.versions but has no submodule in .gitmodules"
    FAIL=1
    continue
  fi
  path=$(git config -f .gitmodules --get "$key")
  tag="v${version#v}"

  # The peeled ^{} line, when present, is the commit an annotated tag points to.
  want=$(git -C "$path" ls-remote origin "refs/tags/${tag}" "refs/tags/${tag}^{}" | tail -n1 | cut -f1)
  have=$(git -C "$path" rev-parse HEAD)

  if [ -z "$want" ]; then
    echo "::error::${module}: tag ${tag} does not exist in its repo"
    FAIL=1
  elif [ "$want" != "$have" ]; then
    echo "::error::${path} is at ${have:0:8}, but modules.versions pins ${module} ${tag} (${want:0:8}). Move the submodule to ${tag} in the same PR."
    FAIL=1
  else
    echo "  ok  ${path} at ${tag}"
  fi
done < modules.versions

exit $FAIL
