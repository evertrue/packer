TEST?=./...
# Get the current full sha from git
GITSHA:=$(shell git rev-parse HEAD)
# Get the current local branch name from git (if we can, this may be blank)
GITBRANCH:=$(shell git symbolic-ref --short HEAD 2>/dev/null)

default: test vet dev

deps: verifysha depsinternal verifysha

ci: deps test vet

release: checkversion deps test vet bin

# `go get` will sometimes revert to master, which is not what we want.
# We check the git sha when make starts and verify periodically to avoid drift.
# Don't use -f for this because it will wipe out your changes in development.
verifysha:
	@if [ "$(GITBRANCH)" != "" ]; then git checkout -q $(GITBRANCH); else git checkout -q $(GITSHA); fi
	@if [ `git rev-parse HEAD` != "$(GITSHA)" ]; then \
		echo "ERROR: git checkout has drifted and we weren't able to correct it. Was $(GITBRANCH) ($(GITSHA))"; \
		exit 1; \
	fi
	@echo "INFO: Currently on $(GITBRANCH) ($(GITSHA))"

bin: verifysha
	@sh -c "$(CURDIR)/scripts/build.sh"

dev:
	@PACKER_DEV=1 sh -c "$(CURDIR)/scripts/build.sh"

# generate runs `go generate` to build the dynamically generated
# source files.
generate:
	go generate ./...

test: verifysha
	go test $(TEST) $(TESTARGS) -timeout=15s
	@$(MAKE) vet

# testacc runs acceptance tests
testacc: generate
	@echo "WARN: Acceptance tests will take a long time to run and may cost money. Ctrl-C if you want to cancel."
	PACKER_ACC=1 go test -v $(TEST) $(TESTARGS) -timeout=45m

testrace:
	go test -race $(TEST) $(TESTARGS) -timeout=15s

checkversion:
	@grep 'const VersionPrerelease = ""' version.go > /dev/null || \
		echo "ERROR: You must remove prerelease tags from version.go prior to release." && \
		exit 1

# Don't call this directly. Use deps instead. The reason is that we have to use
# make dependency targets to verifysha, and we can't call them via $(MAKE) or
# they will execute in a submake which may be operating on a different commit.
depsinternal:
	@git diff-index --quiet HEAD ; if [ $$? -ne 0 ]; then \
		echo "ERROR: Your git working tree has uncommitted changes. deps will fail. Please stash or commit your changes first." ; \
		exit 1 ; \
	fi
	go get -u github.com/mitchellh/gox
	go get -u golang.org/x/tools/cmd/stringer
	go list ./... \
		| xargs go list -f '{{join .Deps "\n"}}' \
		| grep -v github.com/mitchellh/packer \
		| grep -v '/internal/' \
		| sort -u \
		| xargs go get -f -u -v -d

updatedeps:
	@echo "WARN: Please use `make deps` instead."
	$(MAKE) deps

vet: verifysha
	@go vet 2>/dev/null ; if [ $$? -eq 3 ]; then \
		go get golang.org/x/tools/cmd/vet; \
	fi
	@go vet $(TEST) ; if [ $$? -eq 1 ]; then \
		echo "ERROR: Vet found problems in the code."; \
		exit 1; \
	fi

.PHONY: bin default generate test testacc updatedeps vet deps depsinternal checkversion ci verifysha
