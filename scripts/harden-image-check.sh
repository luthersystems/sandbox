#!/usr/bin/env bash
# Check a built service image with the build-harden kit (luthersystems/buildenv).
#
# Why: the service image starts FROM service-base-alpine, which runs the kit
# when buildenv builds it. The layers this repo adds after FROM are not
# checked there. This check runs on the finished image, so it proves the
# image that ships holds no distrusted CA (luthersystems/buildenv#163).
#
# How: copy the kit out of the image that HARDEN_KIT names (pinned by digest
# in common.config.mk, next to BUILDENV_TAG) and run its check/image.sh on the image.
# The check exports the image and reads it on the host, so an image of
# another architecture needs no emulation. It needs docker, openssl and bash.
#
# Usage: scripts/harden-image-check.sh [--platform P] IMAGE
# Set HARDEN_KIT to check with another kit.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
kit=${HARDEN_KIT:-$(sed -n 's/^HARDEN_KIT=//p' "$repo/common.config.mk")}
case $kit in
luthersystems/build-harden:*@sha256:*) ;;
*) echo "harden-image-check: HARDEN_KIT must be luthersystems/build-harden:<tag>@sha256:<digest>, not '$kit'" >&2; exit 2 ;;
esac

work=$(mktemp -d)
cid=
cleanup() {
	[ -z "$cid" ] || docker rm "$cid" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT

docker pull -q "$kit" >/dev/null
cid=$(docker create "$kit" /nonexistent)
docker cp "$cid:/harden" "$work/harden"
bash "$work/harden/check/image.sh" "$@"
