#!/usr/bin/env bash
# Compare a Nextcloud app's .gitignore, .nextcloudignore and Makefile with the
# shared versions in this skill, check the npm/composer script names the
# Makefile calls, and list what a release built from HEAD would contain.
# Read-only: writes only to a temporary directory.
#
# Usage: check-project-files.sh <app-dir> [--ship-list]
# Codes: OK, DRIFT (shared part differs), MISSING, NEGATION (! line in
# .nextcloudignore), SCRIPT (missing npm/composer script).
set -uo pipefail

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?usage: check-project-files.sh <app-dir> [--ship-list]}"
ship_list="${2:-}"
cd "$app" || exit 2
marker='# --- App-specific (below this line) ---'
problems=0

shared_part() { awk -v m="$marker" '{ print } $0 == m { exit }' "$1"; }

compare() {  # <file in app> <asset name>
	local file=$1 asset="$skill_dir/assets/$2"
	if [ ! -f "$file" ]; then echo "MISSING   $file"; problems=$((problems + 1)); return; fi
	if ! grep -qxF -- "$marker" "$file"; then
		echo "DRIFT     $file: no App-specific marker line; whole file compared"
	fi
	if diff -q <(shared_part "$file") <(shared_part "$asset") >/dev/null; then
		echo "OK        $file"
	else
		echo "DRIFT     $file (- shared, + this app):"
		diff -u <(shared_part "$asset") <(shared_part "$file") | tail -n +3 | grep '^[-+]' | sed 's/^/          /'
		problems=$((problems + 1))
	fi
}

compare .gitignore gitignore
compare .nextcloudignore nextcloudignore
compare Makefile app.mk

if [ -f .nextcloudignore ] && grep -q '^!' .nextcloudignore; then
	echo "NEGATION  .nextcloudignore has ! lines; rsync --exclude-from cannot read them"
	problems=$((problems + 1))
fi

need_script() {  # <json file> <script>
	python3 -c "import json,sys; sys.exit(0 if '$2' in json.load(open('$1')).get('scripts', {}) else 1)" 2>/dev/null \
		|| { echo "SCRIPT    $1 has no \"$2\" script"; problems=$((problems + 1)); }
}
for s in build lint stylelint ts:check; do need_script package.json "$s"; done
if ls vitest.config.* >/dev/null 2>&1; then need_script package.json test; fi
for s in lint cs:check psalm test:unit; do need_script composer.json "$s"; done
if [ -f openapi.json ]; then need_script composer.json openapi; fi

if [ "$ship_list" = "--ship-list" ]; then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	mkdir -p "$tmp/tree" "$tmp/out"
	git archive --format=tar HEAD | tar -x -C "$tmp/tree"
	ignore="$tmp/tree/.nextcloudignore"
	[ -f "$ignore" ] || { ignore="$skill_dir/assets/nextcloudignore"; echo "(HEAD has no .nextcloudignore: using the shared one)"; }
	echo "Shipped from HEAD (plus js/, css/ and vendor/ from the build):"
	rsync -n -a --exclude-from="$ignore" --out-format='%n' "$tmp/tree/" "$tmp/out/" \
		| grep -v '/$' | sort | sed 's/^/          /'
fi

echo "$problems problem(s)"
[ "$problems" -eq 0 ]
