# Support setting various labels on the final image
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

# Build Geth in a stock Go builder container
FROM golang:1.16-alpine as builder

RUN apk add --no-cache gcc musl-dev linux-headers git

ADD . /go-expanse
RUN cd /go-expanse && go run build/ci.go install ./cmd/gexp

# Pull Geth into a second stage deploy alpine container
FROM alpine:latest

RUN apk add --no-cache ca-certificates
COPY --from=builder /go-expanse/build/bin/gexp /usr/local/bin/

EXPOSE 9656 9656 42786 42786/udp
ENTRYPOINT ["gexp"]

# Add some metadata labels to help programatic image consumption
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

LABEL commit="$COMMIT" version="$VERSION" buildnum="$BUILDNUM"
