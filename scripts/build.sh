#!/usr/bin/env bash

set -euxo pipefail

SVC_PKG="$(go list -buildvcs=false ./${SERVICE_DIR})" \
GO_LD_FLAGS="-X ${SVC_PKG}/version.Version=${VERSION} -extldflags '-static'"

CGO_ENABLED=0 GOOS=linux \
  go build -a \
  -installsuffix "${GO_BUILD_TAGS}" \
  -tags "${GO_BUILD_TAGS}" \
  -ldflags "${GO_LD_FLAGS}" \
  -o app \
  "./${SERVICE_DIR}"
