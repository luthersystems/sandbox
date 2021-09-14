#!/usr/bin/env bash

set -euxo pipefail

SVC_PKG="$(go list ./${SERVICE_DIR})" \
GO_LD_FLAGS="-X ${SVC_PKG}/version.Version=${VERSION} -extldflags '-static'"

CGO_ENABLED=1 GOOS=linux CGO_LDFLAGS_ALLOW="-Wl,--no-as-needed" \
    go build -a \
    -installsuffix "${GO_BUILD_TAGS}" \
    -tags "${GO_BUILD_TAGS}" \
    -ldflags "${GO_LD_FLAGS}" \
    -o app \
    "./${SERVICE_DIR}"
