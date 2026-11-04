#!/usr/bin/env bash
# Works out the version of a CI build and writes it to $GITHUB_ENV:
#   CHIPDECK_VERSION  e.g. 0.4.0 (release, from a v0.4.0 tag) or
#                     0.4.0-test.57 (any other build)
#   CHIPDECK_BUILD    the CI run number (Android versionCode, Windows build)
# The base version is the one in app/pubspec.yaml; bump it there.
set -euo pipefail
base="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' app/pubspec.yaml)"
run="${GITHUB_RUN_NUMBER:-0}"
ref="${GITHUB_REF:-}"
if [[ "$ref" == refs/tags/v* ]]; then
  tag="${ref#refs/tags/v}"
  if [[ "$tag" != "$base" ]]; then
    echo "::error::Tag v$tag does not match pubspec version $base"
    exit 1
  fi
  version="$base"
else
  version="$base-test.$run"
fi
echo "Version: $version (build $run)"
echo "CHIPDECK_VERSION=$version" >> "${GITHUB_ENV:-/dev/stdout}"
echo "CHIPDECK_BUILD=$run" >> "${GITHUB_ENV:-/dev/stdout}"
