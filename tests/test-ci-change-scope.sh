#!/usr/bin/env bash
# Real Git-history regressions; no Docker, GitHub credentials or network.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
planner="$repo/scripts/ci-change-scope.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
git init -q -b main "$tmpdir"
cd "$tmpdir"
git config user.name 'CI scope test'
git config user.email 'ci-scope@example.invalid'
git config commit.gpgsign false

commit() {
    git add .
    git commit -qm "$1"
    git rev-parse HEAD
}
expect_scope() {
    local label="$1" expected="$2" actual
    shift 2
    actual="$(bash "$planner" "$@")"
    if [ "$(jq -Sc . <<<"$actual")" != "$(jq -Sc . <<<"$expected")" ]; then
        printf 'FAIL %s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
    printf 'PASS %s\n' "$label"
}

mkdir -p extensions/{alpha,bravo,charlie} .github/workflows scripts
echo 'source' > extensions/alpha/Dockerfile
echo 'APT_PACKAGE="bravo"' > extensions/bravo/extension.conf
echo 'APT_PACKAGE="charlie"' > extensions/charlie/extension.conf
echo 'custom apt' > extensions/charlie/Dockerfile
echo '{"bravo":{"19":"1"},"charlie":{"19":"1"}}' > .github/apt-versions.json
echo '{}' > .github/base-image-digests.json
echo baseline > README.md
initial="$(commit baseline)"

# Reproduce a rebase merge: extension code first, documentation last.
echo updated >> extensions/alpha/Dockerfile
commit 'change source layer' >/dev/null
echo documentation >> README.md
head="$(commit 'docs-only final commit')"
expect_scope 'push includes earlier source changes before docs' \
    '{"changed":["alpha"],"build_all":false}' push "$initial" "$head"
expect_scope 'PR includes all commits, not just its last commit' \
    '{"changed":["alpha"],"build_all":false}' pull_request "$initial" "$head"
expect_scope 'docs-only push does not select layers' \
    '{"changed":[],"build_all":false}' push "$head~1" "$head"

# A later unrelated main change must not be attributed to the PR.
git switch -qc base-advanced "$initial"
echo unrelated >> extensions/charlie/Dockerfile
advanced="$(commit 'unrelated main layer change')"
expect_scope 'PR uses merge base and excludes unrelated main edits' \
    '{"changed":["alpha"],"build_all":false}' pull_request "$advanced" "$head"

# The old APT snapshot must come from the full range's base, not HEAD~1.
git switch -qc apt-update "$initial"
echo '{"bravo":{"19":"2"},"charlie":{"19":"1"}}' > .github/apt-versions.json
commit 'update APT version' >/dev/null
echo documentation >> README.md
apt_head="$(commit 'docs after APT update')"
# Dirty worktree data must not influence the selected head snapshot.
echo '{"charlie":{"19":"999"}}' > .github/apt-versions.json
expect_scope 'APT delta uses event snapshots despite docs or dirty worktree' \
    '{"changed":["bravo"],"build_all":false}' push "$initial" "$apt_head"
expect_scope 'PR detects earlier APT updates' \
    '{"changed":["bravo"],"build_all":false}' pull_request "$initial" "$apt_head"
# Restore only this fixture's deliberate edit before switching branches.
git show "$apt_head:.github/apt-versions.json" > .github/apt-versions.json

git switch -qc apt-template "$initial"
echo template > Dockerfile.apt
commit 'shared template change' >/dev/null
echo documentation >> README.md
head="$(commit 'docs after template')"
expect_scope 'shared APT template includes only template consumers' \
    '{"changed":["bravo"],"build_all":false}' push "$initial" "$head"

# Every plumbing trigger must survive a docs-only final commit, just like #179.
index=0
for path in .github/base-image-digests.json .github/workflows/ci.yml Makefile scripts/build.sh; do
    index=$((index + 1))
    git switch -qc "plumbing-$index" "$initial"
    echo updated >> "$path"
    commit 'plumbing change' >/dev/null
    echo documentation >> README.md
    head="$(commit 'docs after plumbing')"
    expect_scope "full rebuild/promotion for earlier $path change" \
        '{"changed":[],"build_all":true}' push "$initial" "$head"
done

expect_scope 'new-branch push compares the entire tree' \
    '{"changed":["alpha","bravo","charlie"],"build_all":true}' \
    push 0000000000000000000000000000000000000000 "$initial"

for event in push pull_request; do
    if bash "$planner" "$event" deadbeef "$initial" > result.json 2>/dev/null; then
        echo "FAIL $event accepted an unavailable base" >&2
        exit 1
    fi
    [ ! -s result.json ] || { echo 'FAIL invalid range emitted a valid-looking scope' >&2; exit 1; }
    echo "PASS $event fails closed on an unavailable base"
done

# Workflow wiring is part of the regression: full history and event SHA inputs
# must remain configured, and no last-commit-only Git commands may return.
workflow="$repo/.github/workflows/ci.yml"
for text in 'fetch-depth: 0' 'github.event.pull_request.base.sha || github.event.before' \
    'github.event.pull_request.head.sha || github.sha' 'bash ./scripts/ci-change-scope.sh'; do
    grep -qF "$text" "$workflow" || { echo "FAIL workflow missing: $text" >&2; exit 1; }
done
if grep -Eq 'git (diff|show).*HEAD~1' "$workflow"; then
    echo 'FAIL CI must not plan changes from the last commit only' >&2
    exit 1
fi
echo 'PASS CI wires full event history and the tested change-scope planner'
