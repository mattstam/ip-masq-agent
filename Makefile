# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The binary to build (just the basename).
BIN := ip-masq-agent

# This repo's root import path (under GOPATH).
PKG := k8s.io/ip-masq-agent

# Where to push the docker image.
REGISTRY ?= gcr.io/k8s-staging-networking

# Which architecture to build - see $(ALL_ARCH) for options.
ARCH ?= amd64

# This version-strategy uses git tags to set the version string
VERSION := $(shell git describe --tags --always --dirty)
#
# This version-strategy uses a manual value to set the version string
#VERSION := 1.2.3

###
### These variables should not need tweaking.
###

SRC_DIRS := cmd pkg # directories which hold app source (not vendored)

ALL_ARCH := amd64 arm arm64 ppc64le

# Ensure that the docker command line supports the manifest images
export DOCKER_CLI_EXPERIMENTAL=enabled

# docker interactive console
INTERACTIVE := $(shell [ -t 0 ] && echo 1 || echo 0)
TTY=
ifeq ($(INTERACTIVE), 1)
    TTY=t
endif

# Set default base image dynamically for each arch
ifeq ($(ARCH),amd64)
    BASEIMAGE?=k8s.gcr.io/build-image/debian-iptables-amd64:buster-v1.7.0
endif
ifeq ($(ARCH),arm)
    BASEIMAGE?=k8s.gcr.io/build-image/debian-iptables-arm:buster-v1.7.0
endif
ifeq ($(ARCH),arm64)
    BASEIMAGE?=k8s.gcr.io/build-image/debian-iptables-arm64:buster-v1.7.0
endif
ifeq ($(ARCH),ppc64le)
    BASEIMAGE?=k8s.gcr.io/build-image/debian-iptables-ppc64le:buster-v1.7.0
endif

IMAGE := $(REGISTRY)/$(BIN)-$(ARCH)
MANIFEST_IMAGE := $(REGISTRY)/$(BIN)

BUILD_IMAGE ?= golang:1.11-alpine

# If you want to build all binaries, see the 'all-build' rule.
# If you want to build all containers, see the 'all-container' rule.
# If you want to build AND push all containers, see the 'all-push' rule.
all: build

build-%:
	@$(MAKE) --no-print-directory ARCH=$* build

container-%:
	@$(MAKE) --no-print-directory ARCH=$* container

push-%:
	@$(MAKE) --no-print-directory ARCH=$* push

all-build: $(addprefix build-, $(ALL_ARCH))

all-container: $(addprefix container-, $(ALL_ARCH))

all-push: $(addprefix push-, $(ALL_ARCH))
	docker manifest create --amend $(MANIFEST_IMAGE):$(VERSION) $(shell echo $(ALL_ARCH) | sed -e "s~[^ ]*~$(MANIFEST_IMAGE)\-&:$(VERSION)~g")
	@for arch in $(ALL_ARCH); do docker manifest annotate --arch $${arch} ${MANIFEST_IMAGE}:${VERSION} ${MANIFEST_IMAGE}-$${arch}:${VERSION}; done
	docker manifest push --purge ${MANIFEST_IMAGE}:${VERSION}

build: bin/$(ARCH)/$(BIN)

bin/$(ARCH)/$(BIN): build-dirs
	@echo "building: $@"
	@docker pull $(BUILD_IMAGE)
	@docker run                                                            \
	    -$(TTY)i                                                           \
	    -u $$(id -u):$$(id -g)                                             \
	    -v $$(pwd)/.go:/go                                                 \
	    -v $$(pwd):/go/src/$(PKG)                                          \
	    -v $$(pwd)/bin/$(ARCH):/go/bin                                     \
	    -v $$(pwd)/bin/$(ARCH):/go/bin/linux_$(ARCH)                       \
	    -v $$(pwd)/.go/std/$(ARCH):/usr/local/go/pkg/linux_$(ARCH)_static  \
	    -w /go/src/$(PKG)                                                  \
            -e GOCACHE=off                                                     \
	    $(BUILD_IMAGE)                                                     \
	    /bin/sh -c "                                                       \
	        ARCH=$(ARCH)                                                   \
	        VERSION=$(VERSION)                                             \
	        PKG=$(PKG)                                                     \
	        ./build/build.sh                                               \
	    "

DOTFILE_IMAGE = $(subst :,_,$(subst /,_,$(IMAGE))-$(VERSION))

container: .container-$(DOTFILE_IMAGE) container-name
.container-$(DOTFILE_IMAGE): bin/$(ARCH)/$(BIN) Dockerfile.in
	@sed \
	    -e 's|ARG_BIN|$(BIN)|g' \
	    -e 's|ARG_ARCH|$(ARCH)|g' \
	    -e 's|ARG_FROM|$(BASEIMAGE)|g' \
	    Dockerfile.in > .dockerfile-$(ARCH)
	@docker build --pull -t $(IMAGE):$(VERSION) -f .dockerfile-$(ARCH) .
	@docker images -q $(IMAGE):$(VERSION) > $@

container-name:
	@echo "container: $(IMAGE):$(VERSION)"

push: .push-$(DOTFILE_IMAGE) push-name
.push-$(DOTFILE_IMAGE): .container-$(DOTFILE_IMAGE)
	@docker push $(IMAGE):$(VERSION)
	@docker images -q $(IMAGE):$(VERSION) > $@

push-name:
	@echo "pushed: $(IMAGE):$(VERSION)"

version:
	@echo $(VERSION)

test: build-dirs
	@docker run                                                            \
	    -$(TTY)i                                                           \
	    -u $$(id -u):$$(id -g)                                             \
	    -v $$(pwd)/.go:/go                                                 \
	    -v $$(pwd):/go/src/$(PKG)                                          \
	    -v $$(pwd)/bin/$(ARCH):/go/bin                                     \
	    -v $$(pwd)/.go/std/$(ARCH):/usr/local/go/pkg/linux_$(ARCH)_static  \
	    -w /go/src/$(PKG)                                                  \
            -e GOCACHE=off                                                     \
	    $(BUILD_IMAGE)                                                     \
	    /bin/sh -c "                                                       \
	        ./build/test.sh $(SRC_DIRS)                                    \
	    "

build-dirs:
	@mkdir -p bin/$(ARCH)
	@mkdir -p .go/src/$(PKG) .go/pkg .go/bin .go/std/$(ARCH)

clean: container-clean bin-clean

container-clean:
	rm -rf .container-* .dockerfile-* .push-*

bin-clean:
	rm -rf .go bin
