FROM golang:1.18-alpine
WORKDIR /app

ENV STAGE $STAGE

RUN wget https://github.com/githubnemo/CompileDaemon/archive/refs/tags/v1.4.0.tar.gz && \
    tar -xvf v1.4.0.tar.gz && \
    rm v1.4.0.tar.gz && \
    cd CompileDaemon-1.4.0 && \
    go build && \
    cp CompileDaemon /usr/local/bin/ && \
    rm -rf CompileDaemon-1.4.0

COPY go.mod ./
COPY go.sum ./
RUN go mod download
COPY . ./
RUN go build -o /main



EXPOSE 8080
ENTRYPOINT /bin/sh ./scripts/start_container.sh "$STAGE"


