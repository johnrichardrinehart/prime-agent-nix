# shellcheck shell=bash

mode=update
case "${1-}" in
"") ;;
--check) mode=check ;;
--force) mode=force ;;
*)
  echo "Usage: prime-agent-update [--check|--force]" >&2
  exit 2
  ;;
esac

if [ ! -f VERSION.json ] || [ ! -f flake.nix ]; then
  echo "Run prime-agent-update from the prime-agent-nix repository root." >&2
  exit 1
fi

latest_rev="$(
  git ls-remote --tags --refs https://github.com/PrimeIntellect-ai/prime-agent.git 'v*' |
    awk -F/ '{ print $3 }' |
    grep -E '^v[0-9]+(\.[0-9]+)*$' |
    sort -V |
    tail -n1
)"
test -n "$latest_rev"
current_rev="$(jq -r .rev VERSION.json)"

if [ "$mode" = check ]; then
  if [ "$latest_rev" = "$current_rev" ]; then
    echo "Prime Agent is current at $current_rev."
  else
    echo "Prime Agent update available: $current_rev -> $latest_rev"
  fi
  exit 0
fi

if [ "$mode" != force ] && [ "$latest_rev" = "$current_rev" ]; then
  echo "Prime Agent is current at $current_rev."
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_json="$(
  nix store prefetch-file --json --unpack \
    "https://github.com/PrimeIntellect-ai/prime-agent/archive/refs/tags/$latest_rev.tar.gz"
)"
source_hash="$(jq -r .hash <<<"$source_json")"
source_path="$(jq -r .storePath <<<"$source_json")"

cp -R "$source_path"/. "$tmpdir/source"
chmod -R u+w "$tmpdir/source"
npm-lockfile-fix "$tmpdir/source/package-lock.json"

cat >"$tmpdir/npm-deps.nix" <<NIX
let
  pkgs = import $PRIME_AGENT_NIXPKGS { };
in
pkgs.fetchNpmDeps {
  src = $tmpdir/source;
  hash = pkgs.lib.fakeHash;
  fetcherVersion = 2;
}
NIX

set +e
npm_deps_log="$(nix-build "$tmpdir/npm-deps.nix" --no-out-link 2>&1)"
npm_deps_status=$?
set -e
if [ "$npm_deps_status" -eq 0 ]; then
  echo "The fake npm dependency hash unexpectedly succeeded." >&2
  exit 1
fi

npm_deps_hash="$(sed -n 's/^[[:space:]]*got:[[:space:]]*//p' <<<"$npm_deps_log" | tail -n1)"
if [[ ! $npm_deps_hash =~ ^sha256- ]]; then
  printf '%s\n' "$npm_deps_log" >&2
  echo "Could not determine the npm dependency hash." >&2
  exit 1
fi

cp "$tmpdir/source/package-lock.json" package-lock.json
jq \
  --arg rev "$latest_rev" \
  --arg hash "$source_hash" \
  --arg npmDepsHash "$npm_deps_hash" \
  '.rev = $rev | .hash = $hash | .npmDepsHash = $npmDepsHash' \
  VERSION.json >"$tmpdir/VERSION.json"
mv "$tmpdir/VERSION.json" VERSION.json

echo "Updated Prime Agent to $latest_rev."
