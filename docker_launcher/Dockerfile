FROM golang:1.18-alpine
RUN apk add udev lsblk docker
WORKDIR /app
COPY go.mod ./
COPY go.sum ./
RUN go mod download
COPY . ./
RUN go build -o /main

EXPOSE 9000
CMD [ "/main" ]
