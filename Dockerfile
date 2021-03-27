#
# BUILD ENVIRONMENT
# -----------------
ARG GO_VERSION=1.16
FROM golang:${GO_VERSION}-alpine as builder

RUN apk add --no-cache upx

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY main.go main.go
COPY api/ api/
COPY controllers/ controllers/
COPY internal/ internal/
COPY webhooks/ webhooks/
COPY version/ version/
COPY cmd/ cmd/

# Do an initial compilation before setting the version so that there is less to
# re-compile when the version changes
RUN go build -mod=readonly "-ldflags=-s -w" ./...

ARG VERSION
ARG BACKUP_AGENT_IMAGE
ARG RESTORE_AGENT_IMAGE

# Compile all the binaries
RUN go build \
    -mod=readonly \
    -ldflags="-X=github.com/improbable-eng/etcd-cluster-operator/version.Version=${VERSION}\
              -X=main.defaultBackupAgentImage=${BACKUP_AGENT_IMAGE}\
              -X=main.defaultRestoreAgentImage=${RESTORE_AGENT_IMAGE}" \
    -o manager main.go
RUN go build -mod=readonly "-ldflags=-s -w -X=github.com/improbable-eng/etcd-cluster-operator/version.Version=${VERSION}" -o proxy cmd/proxy/main.go
RUN go build -mod=readonly "-ldflags=-s -w -X=github.com/improbable-eng/etcd-cluster-operator/version.Version=${VERSION}" -o backup-agent cmd/backup-agent/main.go
RUN go build -mod=readonly "-ldflags=-s -w -X=github.com/improbable-eng/etcd-cluster-operator/version.Version=${VERSION}" -o restore-agent cmd/restore-agent/main.go

RUN upx manager proxy backup-agent restore-agent

#
# IMAGE TARGETS
# -------------
FROM alpine:3.13 as controller
WORKDIR /
COPY --from=builder /workspace/manager .
ENTRYPOINT ["/manager"]

FROM alpine:3.13 as proxy
WORKDIR /
COPY --from=builder /workspace/proxy .
ENTRYPOINT ["/proxy"]

FROM alpine:3.13 as backup-agent
WORKDIR /
COPY --from=builder /workspace/backup-agent .
ENTRYPOINT ["/backup-agent"]

# restore-agent must run as root
# See https://github.com/improbable-eng/etcd-cluster-operator/issues/139
FROM gcr.io/distroless/static as restore-agent
WORKDIR /
COPY --from=builder /workspace/restore-agent .
USER root:root
ENTRYPOINT ["/restore-agent"]
