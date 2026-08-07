#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-package-matrix.XXXXXXXX")

cleanup() {
	rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

(
	cd "$repository_root"
	node create-matrix.js > "$temporary_directory/matrix.json"
	node -e '
		const matrix = require(process.argv[1]);
		if (!Number.isInteger(matrix.max_tier) || matrix.max_tier < 0) process.exit(1);
		for (let tier = 0; tier <= matrix.max_tier; tier++) {
			if (!Array.isArray(matrix[`tier${tier}_main`])) process.exit(1);
			if (!Array.isArray(matrix[`tier${tier}_slow`])) process.exit(1);
		}
	' "$temporary_directory/matrix.json"

	test -z "$(node create-matrix.js deps-list zlib)"
	test "$(node create-matrix.js deps cpython3)" = \
		'package-@(openssl-1.1.1|bzip2|xz|zlib|zstd|libzip)'
)

printf 'VitaSDK package matrix contracts passed\n'
