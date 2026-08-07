#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf 'usage: %s <repository-directory>\n' "$0" >&2
	exit 2
}

[[ $# -eq 1 ]] || usage

repository_directory=$1
repository_name=${REPOSITORY_NAME:-vita}
expected_architecture=${EXPECTED_ARCHITECTURE:-vita}

[[ -d $repository_directory ]] || {
	printf 'repository directory not found: %s\n' "$repository_directory" >&2
	exit 1
}

repository_directory=$(cd "$repository_directory" && pwd -P)
database="$repository_directory/$repository_name.db"
files_database="$repository_directory/$repository_name.files"
checksums="$repository_directory/SHA256SUMS"

for required_file in "$database" "$files_database" "$checksums"; do
	[[ -f $required_file && ! -L $required_file ]] || {
		printf 'missing regular repository asset: %s\n' "$required_file" >&2
		exit 1
	}
done

if find "$repository_directory" -mindepth 1 ! -type f -print -quit | grep -q .; then
	printf 'repository contains a directory or non-regular asset\n' >&2
	exit 1
fi

mapfile -d '' packages < <(
	find "$repository_directory" -maxdepth 1 -type f -name '*.pkg.tar.*' \
		-print0 | LC_ALL=C sort -z
)
(( ${#packages[@]} > 0 )) || {
	printf 'repository contains no packages\n' >&2
	exit 1
}

declare -A package_names=()
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-repository-validation.XXXXXXXX")
cleanup() {
	rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

package_filenames="$temporary_directory/package-filenames"
database_filenames="$temporary_directory/database-filenames"
database_entries="$temporary_directory/database-entries"
files_entries="$temporary_directory/files-entries"

for package in "${packages[@]}"; do
	package_filename=${package##*/}
	pkginfo=$(bsdtar -xOf "$package" .PKGINFO) || {
		printf 'cannot read .PKGINFO from %s\n' "$package_filename" >&2
		exit 1
	}

	pkgname=$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<< "$pkginfo")
	pkgver=$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<< "$pkginfo")
	architecture=$(awk -F ' = ' '$1 == "arch" { print $2; exit }' <<< "$pkginfo")

	[[ -n $pkgname && -n $pkgver && $architecture == "$expected_architecture" ]] || {
		printf 'invalid identity or architecture in %s\n' "$package_filename" >&2
		exit 1
	}
	[[ $package_filename == "$pkgname-$pkgver-$architecture.pkg.tar."* ]] || {
		printf 'filename does not match package metadata: %s\n' "$package_filename" >&2
		exit 1
	}
	[[ -z ${package_names[$pkgname]+present} ]] || {
		printf 'repository contains more than one package named %s\n' "$pkgname" >&2
		exit 1
	}
	package_names[$pkgname]=1

	archive_entries=$(bsdtar -tf "$package")
	for metadata in .PKGINFO .BUILDINFO .MTREE; do
		grep -qx "$metadata" <<< "$archive_entries" || {
			printf '%s is missing from %s\n' "$metadata" "$package_filename" >&2
			exit 1
		}
	done
	if grep -Ev '^(\.PKGINFO|\.BUILDINFO|\.MTREE|arm-vita-eabi(/.*)?)$' \
			<<< "$archive_entries"; then
		printf 'package contains a path outside the VitaSDK target root: %s\n' \
			"$package_filename" >&2
		exit 1
	fi
	bsdtar -xOf "$package" .MTREE | gzip -t
	printf '%s\n' "$package_filename" >> "$package_filenames"
done

LC_ALL=C sort -o "$package_filenames" "$package_filenames"

bsdtar -tf "$database" | LC_ALL=C sort > "$database_entries"
bsdtar -tf "$files_database" | LC_ALL=C sort > "$files_entries"

while IFS= read -r description; do
	bsdtar -xOf "$database" "$description" |
		awk 'previous == "%FILENAME%" { print; exit } { previous = $0 }'
done < <(grep '/desc$' "$database_entries") | LC_ALL=C sort > "$database_filenames"

diff -u "$package_filenames" "$database_filenames"

while IFS= read -r entry; do
	grep -qx "$entry" "$files_entries" || {
		printf 'files database is missing entry: %s\n' "$entry" >&2
		exit 1
	}
done < "$database_entries"

expected_checksum_files="$temporary_directory/expected-checksum-files"
actual_checksum_files="$temporary_directory/actual-checksum-files"
find "$repository_directory" -maxdepth 1 -type f ! -name SHA256SUMS \
	-printf '%f\n' | LC_ALL=C sort > "$expected_checksum_files"
awk '{ sub(/^\*/, "", $2); print $2 }' "$checksums" |
	LC_ALL=C sort > "$actual_checksum_files"
diff -u "$expected_checksum_files" "$actual_checksum_files"

(
	cd "$repository_directory"
	sha256sum --check --strict SHA256SUMS
)

printf 'validated %s repository with %d packages\n' \
	"$repository_name" "${#packages[@]}"
