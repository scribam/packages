#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf 'usage: %s <output-directory> <package>...\n' "$0" >&2
	exit 2
}

[[ $# -ge 2 ]] || usage

output_directory=$1
shift

repository_name=${REPOSITORY_NAME:-vita}
source_date_epoch=${SOURCE_DATE_EPOCH:-}
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

[[ $repository_name =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
	printf 'invalid repository name: %s\n' "$repository_name" >&2
	exit 1
}
[[ -n $source_date_epoch && $source_date_epoch =~ ^[0-9]+$ ]] || {
	printf 'SOURCE_DATE_EPOCH must be set to a non-negative integer\n' >&2
	exit 1
}
command -v repo-add >/dev/null || {
	printf 'repo-add is required to create a repository\n' >&2
	exit 1
}
command -v bsdtar >/dev/null || {
	printf 'bsdtar is required to create a repository\n' >&2
	exit 1
}

output_parent=$(cd "$(dirname "$output_directory")" && pwd -P)
output_name=$(basename "$output_directory")
[[ ! -e $output_directory ]] || {
	printf 'output path already exists: %s\n' "$output_directory" >&2
	exit 1
}

staging_directory=$(mktemp -d "$output_parent/.${output_name}.XXXXXXXX")
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-repository.XXXXXXXX")
cleanup() {
	rm -rf -- "$staging_directory" "$temporary_directory"
}
trap cleanup EXIT

declare -A package_filenames=()
packages=()
for package in "$@"; do
	[[ -f $package && ! -L $package ]] || {
		printf 'package is not a regular file: %s\n' "$package" >&2
		exit 1
	}
	package=$(cd "$(dirname "$package")" && pwd -P)/$(basename "$package")
	package_filename=${package##*/}
	[[ $package_filename == *.pkg.tar.* ]] || {
		printf 'not a pacman package: %s\n' "$package_filename" >&2
		exit 1
	}
	[[ -z ${package_filenames[$package_filename]+present} ]] || {
		printf 'duplicate package filename: %s\n' "$package_filename" >&2
		exit 1
	}
	package_filenames[$package_filename]=1
	cp -p "$package" "$staging_directory/$package_filename"
	packages+=("$staging_directory/$package_filename")
done

mapfile -t packages < <(printf '%s\n' "${packages[@]}" | LC_ALL=C sort)

repo-add "$staging_directory/$repository_name.db.tar.gz" "${packages[@]}"

normalize_database() {
	local source_archive=$1 output_archive=$2 extraction_directory list_file
	extraction_directory=$(mktemp -d "$temporary_directory/database.XXXXXXXX")
	list_file=$(mktemp "$temporary_directory/database-list.XXXXXXXX")
	bsdtar -xf "$source_archive" -C "$extraction_directory"
	find "$extraction_directory" -exec touch -h -d "@$source_date_epoch" {} +
	(
		cd "$extraction_directory"
		find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort > "$list_file"
		bsdtar --format=gnutar --uid 0 --gid 0 --uname root --gname root \
			-cnf - -T "$list_file" | gzip -9 -n > "$output_archive"
	)
}

normalize_database "$staging_directory/$repository_name.db.tar.gz" \
	"$temporary_directory/$repository_name.db"
normalize_database "$staging_directory/$repository_name.files.tar.gz" \
	"$temporary_directory/$repository_name.files"

rm -f "$staging_directory/$repository_name.db" \
	"$staging_directory/$repository_name.db.tar.gz" \
	"$staging_directory/$repository_name.files" \
	"$staging_directory/$repository_name.files.tar.gz"
mv "$temporary_directory/$repository_name.db" "$staging_directory/$repository_name.db"
mv "$temporary_directory/$repository_name.files" "$staging_directory/$repository_name.files"

(
	cd "$staging_directory"
	while IFS= read -r asset; do
		sha256sum -- "$asset"
	done < <(
		find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' |
			LC_ALL=C sort
	) > SHA256SUMS
)

REPOSITORY_NAME=$repository_name \
	"$script_directory/validate-repository.sh" "$staging_directory"

mv "$staging_directory" "$output_directory"
printf 'created repository: %s\n' "$output_directory"
