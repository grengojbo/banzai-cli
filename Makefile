# A Self-Documenting Makefile: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html

OS = $(shell uname | tr A-Z a-z)

# Project variables
PACKAGE = github.com/banzaicloud/banzai-cli
BINARY_NAME = banzai

# Build variables
BUILD_DIR ?= build
BUILD_PACKAGE = ${PACKAGE}/cmd/banzai
VERSION ?= $(shell git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD)
COMMIT_HASH ?= $(shell git rev-parse --short HEAD 2>/dev/null)
BUILD_DATE ?= $(shell date +%FT%T%z)
LDFLAGS += -X main.version=${VERSION} -X main.commitHash=${COMMIT_HASH} -X main.buildDate=${BUILD_DATE} -X main.pipelineVersion=${PIPELINE_VERSION}
export CGO_ENABLED ?= 0
ifeq (${VERBOSE}, 1)
ifeq ($(filter -v,${GOARGS}),)
	GOARGS += -v
endif
TEST_FORMAT = short-verbose
endif

PIPELINE_VERSION = 0.35.0
CLOUDINFO_VERSION = 0.7.8
TELESCOPES_VERSION = 0.5.2

# Dependency versions
GOTESTSUM_VERSION = 0.3.5
GOLANGCI_VERSION = 1.18.0
LICENSEI_VERSION = 0.1.0
GORELEASER_VERSION = 0.112.2
PACKR_VERSION = 2.6.0
OPENAPI_GENERATOR_VERSION = v4.2.2

GOLANG_VERSION = 1.12

# Add the ability to override some variables
# Use with care
-include override.mk

bin/packr2: bin/packr2-${PACKR_VERSION}
	@ln -sf packr2-${PACKR_VERSION} bin/packr2
bin/packr2-${PACKR_VERSION}:
	@mkdir -p bin
	curl -L https://github.com/gobuffalo/packr/releases/download/v${PACKR_VERSION}/packr_${PACKR_VERSION}_${OS}_amd64.tar.gz | tar -zOxf - packr2 > ./bin/packr2-${PACKR_VERSION} && chmod +x ./bin/packr2-${PACKR_VERSION}

.PHONY: client-build
client-build: ## Build form client
	@${MAKE} -C internal/cli/command/form/web build

.PHONY: client-bundle
client-bundle: bin/packr2 ## Bundle client assets
	cd internal/cli/command/form && $(abspath bin/packr2)

.PHONY: pre-build
pre-build: ## Pre build bundles of static assets
	@${MAKE} client-build
	@${MAKE} client-bundle

.PHONY: build
build: ## Build a binary
ifeq (${VERBOSE}, 1)
	go env
endif
ifneq (${IGNORE_GOLANG_VERSION_REQ}, 1)
	@printf "${GOLANG_VERSION}\n$$(go version | awk '{sub(/^go/, "", $$3);print $$3}')" | sort -t '.' -k 1,1 -k 2,2 -k 3,3 -g | head -1 | grep -q -E "^${GOLANG_VERSION}$$" || (printf "Required Go version is ${GOLANG_VERSION}\nInstalled: `go version`" && exit 1)
endif
	go build ${GOARGS} -tags "${GOTAGS}" -ldflags "${LDFLAGS}" -o ${BUILD_DIR}/${BINARY_NAME} ${BUILD_PACKAGE}

.PHONY: build-debug
build-debug: ## Build a binary with remote debugging capabilities
	@${MAKE} GOARGS="${GOARGS} -gcflags \"all=-N -l\"" BUILD_DIR="${BUILD_DIR}/debug" build

.PHONY: debug
debug: build-debug
	dlv --listen=:40000 --log --headless=true --api-version=2 exec "${BUILD_DIR}/debug/${BINARY_NAME}" -- ${ARGS}

.PHONY: build-release
build-release: LDFLAGS += -w
build-release: pre-build build ## Build a binary without debug information

.PHONY: generate-banzai-cli-docs
generate-banzai-cli-docs: ## Generate documentation for Banzai CLI
	rm -rf cmd/docs/*.md
	cd cmd/docs/ && go run -v generate.go

.PHONY: check
check: test lint ## Run tests and linters

bin/gotestsum: bin/gotestsum-${GOTESTSUM_VERSION}
	@ln -sf gotestsum-${GOTESTSUM_VERSION} bin/gotestsum
bin/gotestsum-${GOTESTSUM_VERSION}:
	@mkdir -p bin
	curl -L https://github.com/gotestyourself/gotestsum/releases/download/v${GOTESTSUM_VERSION}/gotestsum_${GOTESTSUM_VERSION}_${OS}_amd64.tar.gz | tar -zOxf - gotestsum > ./bin/gotestsum-${GOTESTSUM_VERSION} && chmod +x ./bin/gotestsum-${GOTESTSUM_VERSION}

TEST_PKGS ?= ./...
TEST_REPORT_NAME ?= results.xml
.PHONY: test
test: TEST_REPORT ?= main
test: TEST_FORMAT ?= short
test: SHELL = /bin/bash
test: bin/gotestsum ## Run tests
	@mkdir -p ${BUILD_DIR}/test_results/${TEST_REPORT}
	bin/gotestsum --no-summary=skipped --junitfile ${BUILD_DIR}/test_results/${TEST_REPORT}/${TEST_REPORT_NAME} --format ${TEST_FORMAT} -- $(filter-out -v,${GOARGS}) $(if ${TEST_PKGS},${TEST_PKGS},./...)

bin/golangci-lint: bin/golangci-lint-${GOLANGCI_VERSION}
	@ln -sf golangci-lint-${GOLANGCI_VERSION} bin/golangci-lint
bin/golangci-lint-${GOLANGCI_VERSION}:
	@mkdir -p bin
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | bash -s -- -b ./bin/ v${GOLANGCI_VERSION}
	@mv bin/golangci-lint $@

.PHONY: lint
lint: bin/golangci-lint ## Run linter
	bin/golangci-lint run

bin/licensei: bin/licensei-${LICENSEI_VERSION}
	@ln -sf licensei-${LICENSEI_VERSION} bin/licensei
bin/licensei-${LICENSEI_VERSION}:
	@mkdir -p bin
	curl -sfL https://raw.githubusercontent.com/goph/licensei/master/install.sh | bash -s v${LICENSEI_VERSION}
	@mv bin/licensei $@

.PHONY: license-check
license-check: bin/licensei ## Run license check
	bin/licensei check
	./scripts/check-header.sh

.PHONY: license-cache
license-cache: bin/licensei ## Generate license cache
	bin/licensei cache

.PHONY: generate-pipeline-client
generate-pipeline-client: ## Generate client from Pipeline OpenAPI spec
	curl https://raw.githubusercontent.com/banzaicloud/pipeline/${PIPELINE_VERSION}/apis/pipeline/pipeline.yaml > pipeline-openapi.yaml
	rm -rf .gen/pipeline
	docker run --rm -v ${PWD}:/local openapitools/openapi-generator-cli:${OPENAPI_GENERATOR_VERSION} generate \
	--additional-properties packageName=pipeline \
	--additional-properties withGoCodegenComment=true \
	-i /local/pipeline-openapi.yaml \
	-g go \
	-o /local/.gen/pipeline
	echo "package pipeline\n\nconst PipelineVersion = \"${PIPELINE_VERSION}\"" > .gen/pipeline/version.go
	sed 's#jsonCheck = .*#jsonCheck = regexp.MustCompile(`(?i:(?:application|text)/(?:(?:vnd\\.[^;]+\\+)|(?:problem\\+))?json)`)#' .gen/pipeline/client.go > .gen/pipeline/client.go.new
	mv .gen/pipeline/client.go.new .gen/pipeline/client.go
	rm .gen/pipeline/{.travis.yml,git_push.sh,go.*}

.PHONY: generate-cloudinfo-client
generate-cloudinfo-client: ## Generate client from Cloudinfo OpenAPI spec
	curl https://raw.githubusercontent.com/banzaicloud/cloudinfo/${CLOUDINFO_VERSION}/api/openapi-spec/cloudinfo.yaml | sed "s/version: .*/version: ${CLOUDINFO_VERSION}/" > cloudinfo-openapi.yaml
	rm -rf .gen/cloudinfo
	docker run --rm -v ${PWD}:/local banzaicloud/openapi-generator-cli:${OPENAPI_GENERATOR_VERSION} generate \
	--additional-properties packageName=cloudinfo \
	--additional-properties withGoCodegenComment=true \
	-i /local/cloudinfo-openapi.yaml \
	-g go \
	-o /local/.gen/cloudinfo

.PHONY: generate-telescopes-client
generate-telescopes-client: ## Generate client from Telescopes OpenAPI spec
	curl https://raw.githubusercontent.com/banzaicloud/telescopes/${TELESCOPES_VERSION}/api/openapi-spec/recommender.yaml | sed "s/version: .*/version: ${TELESCOPES_VERSION}/" > telescopes-openapi.yaml
	rm -rf .gen/telescopes
	docker run --rm -v ${PWD}:/local banzaicloud/openapi-generator-cli:${OPENAPI_GENERATOR_VERSION} generate \
	--additional-properties packageName=telescopes \
	--additional-properties withGoCodegenComment=true \
	-i /local/telescopes-openapi.yaml \
	-g go \
	-o /local/.gen/telescopes

bin/goreleaser: bin/goreleaser-${GORELEASER_VERSION}
	@ln -sf goreleaser-${GORELEASER_VERSION} bin/goreleaser
bin/goreleaser-${GORELEASER_VERSION}:
	@mkdir -p bin
	curl -sfL https://install.goreleaser.com/github.com/goreleaser/goreleaser.sh | bash -s -- -b ./bin/ v${GORELEASER_VERSION}
	@mv bin/goreleaser $@

.PHONY: release
release: bin/goreleaser # Publish a release
	bin/goreleaser release ${GORELEASERFLAGS}

# release-%: TAG_PREFIX = v
release-%:
ifneq (${DRY}, 1)
#	@sed -e "s/^## \[Unreleased\]$$/## [Unreleased]\\"$$'\n'"\\"$$'\n'"\\"$$'\n'"## [$*] - $$(date +%Y-%m-%d)/g; s|^\[Unreleased\]: \(.*\/compare\/\)\(.*\)...HEAD$$|[Unreleased]: \1${TAG_PREFIX}$*...HEAD\\"$$'\n'"[$*]: \1\2...${TAG_PREFIX}$*|g" CHANGELOG.md > CHANGELOG.md.new
#	@mv CHANGELOG.md.new CHANGELOG.md

ifeq (${TAG}, 1)
#	git add CHANGELOG.md
#	git commit -m 'Prepare release $*'
	git tag -m 'Release $*' ${TAG_PREFIX}$*
ifeq (${PUSH}, 1)
	git push; git push origin ${TAG_PREFIX}$*
endif
endif
endif

	@echo "Version updated to $*!"
ifneq (${PUSH}, 1)
	@echo
	@echo "Review the changes made by this script then execute the following:"
ifneq (${TAG}, 1)
	@echo
#	@echo "git add CHANGELOG.md && git commit -m 'Prepare release $*' && git tag -m 'Release $*' ${TAG_PREFIX}$*"
	@echo "git tag -m 'Release $*' ${TAG_PREFIX}$*"
	@echo
	@echo "Finally, push the changes:"
endif
	@echo
	@echo "git push; git push origin ${TAG_PREFIX}$*"
endif

.PHONY: patch
patch: ## Release a new patch version
	@${MAKE} release-$(shell (git describe --abbrev=0 --tags 2> /dev/null || echo "0.0.0") | sed 's/^v//' | awk -F'[ .]' '{print $$1"."$$2"."$$3+1}')

.PHONY: minor
minor: ## Release a new minor version
	@${MAKE} release-$(shell (git describe --abbrev=0 --tags 2> /dev/null || echo "0.0.0") | sed 's/^v//' | awk -F'[ .]' '{print $$1"."$$2+1".0"}')

.PHONY: major
major: ## Release a new major version
	@${MAKE} release-$(shell (git describe --abbrev=0 --tags 2> /dev/null || echo "0.0.0") | sed 's/^v//' | awk -F'[ .]' '{print $$1+1".0.0"}')

.PHONY: list
list: ## List all make targets
	@${MAKE} -pRrn : -f $(MAKEFILE_LIST) 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | sort

.PHONY: help
.DEFAULT_GOAL := help
help:
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# Variable outputting/exporting rules
var-%: ; @echo $($*)
varexport-%: ; @echo $*=$($*)
