FROM google/golang:1.3

WORKDIR /gopath/src/github.com/modcloth/tory
ADD . /gopath/src/github.com/modcloth/tory

RUN go get github.com/tools/godep
RUN make build

CMD ["tory", "serve"]
