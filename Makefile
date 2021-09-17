NAME=gossamer3
ARCH=$(shell uname -m)
ITERATION := 1

SOURCE_FILES?=$$(go list ./... | grep -v /vendor/)
TEST_PATTERN?=.
TEST_OPTIONS?=

BIN_DIR := $(CURDIR)/bin

ci: prepare test

prepare: prepare.metalinter
	GOBIN=$(BIN_DIR) go install github.com/buildkite/github-release
	GOBIN=$(BIN_DIR) go install github.com/mitchellh/gox
	GOBIN=$(BIN_DIR) go install github.com/axw/gocov/gocov
	GOBIN=$(BIN_DIR) go install golang.org/x/tools/cmd/cover

# Gometalinter is deprecated and broken dependency so let's use with GO111MODULE=off
prepare.metalinter:
	GO111MODULE=off go get -u github.com/alecthomas/gometalinter
	GO111MODULE=off gometalinter --fast --install

mod:
	@go mod download
	@go mod tidy

compile: mod
	@rm -rf build/
	@$(BIN_DIR)/gox -ldflags "-X main.Version=$(VERSION)" \
	-osarch="darwin/amd64" \
	-osarch="linux/i386" \
	-osarch="linux/arm64" \
	-osarch="linux/amd64" \
	-osarch="windows/amd64" \
	-osarch="windows/i386" \
	-output "build/{{.Dir}}_$(VERSION)_{{.OS}}_{{.Arch}}/$(NAME)" \
	${SOURCE_FILES}

# Test builds locally without having to worry about hid stuff
build_local:
	rm -rf build
	go mod vendor

# 	Cloning the hid and placing it in the vendor/ directory as a workaround for known Golang issue
#	  https://github.com/golang/go/issues/26366
	git clone https://github.com/karalabe/hid.git
	rm -rf vendor/github.com/karalabe/
	mkdir vendor/github.com/karalabe/
	mv hid vendor/github.com/karalabe/hid/

	GOOS=windows GOARCH=amd64 go build -o build/gossamer_windows_amd64 cmd/gossamer3/*.go
	GOOS=windows GOARCH=386 go build -o build/gossamer_windows_386 cmd/gossamer3/*.go
	GOOS=linux GOARCH=amd64 go build -o build/gossamer_linux_amd64 cmd/gossamer3/*.go
	GOOS=linux GOARCH=arm64 go build -o build/gossamer_linux_arm64 cmd/gossamer3/*.go
# 	GOOS=darwin GOARCH=arm64 go build -o build/gossamer_darwin_arm64 cmd/gossamer3/*.go
#	GOOS=darwin GOARCH=amd64 go build -o build/gossamer_darwin_amd64 cmd/gossamer3/*.go

# 	Replace the vendor with original files
	rm -rf vendor/
	go mod vendor
	go mod verify
	go mod tidy

# Run all the linters
lint:
	@gometalinter --vendor ./...

# gofmt and goimports all go files
fmt:
	find . -name '*.go' -not -wholename './vendor/*' | while read -r file; do gofmt -w -s "$$file"; goimports -w "$$file"; done

install:
	go install ./cmd/gossamer3

dist:
	$(eval FILES := $(shell ls build))
	@rm -rf dist && mkdir dist
	@for f in $(FILES); do \
		(cd $(shell pwd)/build/$$f && tar -cvzf ../../dist/$$f.tar.gz *); \
		(cd $(shell pwd)/dist && shasum -a 256 $$f.tar.gz > $$f.sha256); \
		echo $$f; \
	done

release:
	@$(BIN_DIR)/github-release "v$(VERSION)" dist/* --commit "$(git rev-parse HEAD)" --github-repository GESkunkworks/$(NAME)

test:
	@$(BIN_DIR)/gocov test $(SOURCE_FILES) | $(BIN_DIR)/gocov report

clean:
	@rm -fr ./build

packages:
	rm -rf package && mkdir package
	rm -rf stage && mkdir -p stage/usr/bin
	cp build/gossamer3_*_linux_amd64/gossamer3 stage/usr/bin
	fpm --name $(NAME) -a x86_64 -t rpm -s dir --version $(VERSION) --iteration $(ITERATION) -C stage -p package/$(NAME)-$(VERSION)_$(ITERATION).rpm usr
	fpm --name $(NAME) -a x86_64 -t deb -s dir --version $(VERSION) --iteration $(ITERATION) -C stage -p package/$(NAME)-$(VERSION)_$(ITERATION).deb usr
	shasum -a 512 package/$(NAME)-$(VERSION)_$(ITERATION).rpm > package/$(NAME)-$(VERSION)_$(ITERATION).rpm.sha512
	shasum -a 512 package/$(NAME)-$(VERSION)_$(ITERATION).deb > package/$(NAME)-$(VERSION)_$(ITERATION).deb.sha512

generate-mocks:
	mockery -dir pkg/prompter --all
	mockery -dir pkg/provider/okta -name U2FDevice

.PHONY: default prepare.metalinter prepare mod compile lint fmt dist release test clean generate-mocks
