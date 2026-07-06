build-amd64:
	GOOS=linux GOARCH=amd64 go build -o load_tester_amd64
build-arm64:
	GOOS=linux GOARCH=arm64 go build -o load_tester_arm64

all: build-amd64 build-arm64