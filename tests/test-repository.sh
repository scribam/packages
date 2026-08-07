#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-packages-repository.XXXXXXXX")
pacman_image='archlinux@sha256:c1829f370be8434135f43fb3acaef1256780804ac3b2d2eec90dfb1232e1ffdf'

cleanup() {
	chmod -R u+rwX "$temporary_root" 2>/dev/null || true
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

docker run --rm \
	--platform linux/amd64 \
	--mount "type=bind,source=$repository_root,target=/workspace,readonly" \
	--mount "type=bind,source=$temporary_root,target=/work" \
	--env SOURCE_DATE_EPOCH=1700000000 \
	"$pacman_image" \
	bash -euc '
		export LC_ALL=C
		fixture=/work/fixture
		package=/work/vitasdk-repository-fixture-1.0-1-vita.pkg.tar.xz
		install -d "$fixture/arm-vita-eabi/share/vitasdk-repository-fixture"

		cat > "$fixture/.PKGINFO" <<EOF
pkgname = vitasdk-repository-fixture
pkgbase = vitasdk-repository-fixture
pkgver = 1.0-1
pkgdesc = VitaSDK repository integration fixture
url = https://vitasdk.org/
builddate = 1700000000
packager = VitaSDK Tests
size = 8
arch = vita
license = MIT
xdata = pkgtype=pkg
EOF
		cat > "$fixture/.BUILDINFO" <<EOF
format = 2
pkgname = vitasdk-repository-fixture
pkgver = 1.0-1
pkgarch = vita
builddate = 1700000000
EOF
		printf "fixture\n" > \
			"$fixture/arm-vita-eabi/share/vitasdk-repository-fixture/value.txt"
		(
			cd "$fixture"
			find . -mindepth 1 ! -name .MTREE -print0 | LC_ALL=C sort -z |
				bsdtar -cnf - --format=mtree \
					--options="!all,use-set,type,uid,gid,mode,time,size,sha256,link" \
					--uid 0 --gid 0 --null -T - | gzip -n > .MTREE
		)
		find "$fixture" -exec touch -h -d @1700000000 {} +
		(
			cd "$fixture"
			find . -mindepth 1 -printf "%P\n" | LC_ALL=C sort |
				bsdtar --format=gnutar --uid 0 --gid 0 --uname root --gname root \
					-cnf - -T - | xz -9 -c > "$package"
		)

		/workspace/scripts/create-repository.sh /work/repository-one "$package"
		/workspace/scripts/create-repository.sh /work/repository-two "$package"
		diff -ru /work/repository-one /work/repository-two

		cat > /work/pacman.conf <<EOF
[options]
Architecture = vita
SigLevel = Never
[vita]
Server = file:///work/repository-one
EOF
		install -d /sdk/var/lib/pacman /sdk/var/cache/pacman/pkg
		pacman --config /work/pacman.conf \
			--root /sdk \
			--dbpath /sdk/var/lib/pacman \
			--cachedir /sdk/var/cache/pacman/pkg \
			--logfile /sdk/var/log/pacman.log \
			--noscriptlet --sync --refresh --refresh --noconfirm
		pacman --config /work/pacman.conf \
			--root /sdk \
			--dbpath /sdk/var/lib/pacman \
			--cachedir /sdk/var/cache/pacman/pkg \
			--logfile /sdk/var/log/pacman.log \
			--noscriptlet --sync --noconfirm vitasdk-repository-fixture
		grep -qx fixture \
			/sdk/arm-vita-eabi/share/vitasdk-repository-fixture/value.txt

		cp -a /work/repository-one /work/corrupted-repository
		printf corruption >> \
			/work/corrupted-repository/vitasdk-repository-fixture-1.0-1-vita.pkg.tar.xz
		if /workspace/scripts/validate-repository.sh /work/corrupted-repository; then
			printf "corrupted package was unexpectedly accepted\n" >&2
			exit 1
		fi
	'

printf 'VitaSDK repository creation and validation contracts passed\n'
