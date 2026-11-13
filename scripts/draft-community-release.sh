#!/bin/bash
# Explicit operator action: upload audited assets as a private/reviewable draft.
# Never changes repository visibility, publishes a release, merges, or replaces assets.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/community-distribution.py verify
release_tag="$(python3 -c 'import json; print(json.load(open("release.json"))["tag"])')"
release_repo="$(python3 -c 'import json; print(json.load(open("release.json"))["repository"])')"
release_label="$(python3 -c 'import json; print(json.load(open("release.json"))["version"] + " " + json.load(open("release.json"))["label"])')"
release_directory="dist/$release_tag"
release_revision="$(cat "$release_directory/SOURCE_REVISION.txt")"
# The target must already be reachable in the intended GitHub repository.
gh api "repos/$release_repo/commits/$release_revision" --jq .sha > /dev/null
if gh release view "$release_tag" --repo "$release_repo" > /dev/null 2>&1; then
    echo 'Release already exists. Do not overwrite reviewed or published assets.' >&2
    exit 2
fi
gh release create "$release_tag" --repo "$release_repo" --target "$release_revision" \
    --title "CopySaver $release_label" --draft --prerelease \
    --notes-file "$release_directory/RELEASE_NOTES.md" "$release_directory"/*
echo 'Draft created. Verify downloaded assets, finish review and confirm visibility before publishing.'
