# Build Geth in a stock Go builder container
FROM golang:1.15-alpine as builder

RUN apk add --no-cache make gcc musl-dev linux-headers git

RUN git clone https://github.com/expanse-org/go-expanse.git /go-expanse

WORKDIR /go-expanse

RUN git checkout 'tags/v1.7.2'

RUN make gexp

# Pull Geth into a second stage deploy alpine container
FROM alpine:latest

RUN apk add --no-cache ca-certificates
COPY --from=builder /go-expanse/build/bin/gexp /usr/local/bin/

EXPOSE 9656 9656 42786 42786/udp
ENTRYPOINT ["gexp"]
