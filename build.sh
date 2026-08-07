#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
	printf 'usage: %s <package-directory> [output-directory]\n' "$0" >&2
	exit 2
fi

package_directory=$1
output_directory=${2:-$PWD/package}

[[ -f $package_directory/VITABUILD ]] || {
	printf 'VITABUILD not found: %s\n' "$package_directory" >&2
	exit 1
}

mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd -P)

(
	cd "$package_directory"
	PKGDEST=$output_directory \
	SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH must be set} \
		vita-makepkg --clean --cleanbuild --force --nodeps --noconfirm
)

mapfile -d '' packages < <(
	find "$output_directory" -maxdepth 1 -type f -name '*.pkg.tar.*' -print0
)
(( ${#packages[@]} == 1 )) || {
	printf 'expected exactly one package, found %d\n' "${#packages[@]}" >&2
	exit 1
}

printf '%s\n' "${packages[0]}"
