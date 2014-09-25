#######################################
# VARIABLES
#
# Set these at runtime to override the below defaults.
# e.g.:
# `make DOCKER_OPTS_CMD=/bin/bash console`
# `make USERNAME=root DOCKER_OPTS_CMD=/bin/bash run`
# `make AIRSTACK_IMAGE_TAG=debug build`
#######################################

SHELL = /bin/sh
# Uncomment when debugging Makefile
# SHELL = /bin/sh -xv

#TOP_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TOP_DIR := $(CURDIR)/
CURR_DIR := $(notdir $(patsubst %/,%,$(dir $(TOP_DIR))))
uname_S := $(shell sh -c 'uname -s 2>/dev/null || echo not')
USERNAME := airstack
USERDIR := $(USERNAME)

AIRSTACK_AIRSTACKIGNORE := .airstackignore
AIRSTACK_TEMPLATES_FILES := Dockerfile.core Dockerfile.packages Dockerfile.packages.dev Dockerfile.services Dockerfile.debug Dockerfile.tests
AIRSTACK_TEMPLATES_DIR := .airstack/templates
AIRSTACK_CACHE_DIR := .airstack/cache
AIRSTACK_IMAGE_REPO := airstack
AIRSTACK_IMAGE_NAME := $(shell cat $(CURDIR)/env/AIRSTACK_IMAGE_NAME)
AIRSTACK_IMAGE_TAG := latest
AIRSTACK_IMAGE_FULLNAME := $(AIRSTACK_IMAGE_REPO)/$(AIRSTACK_IMAGE_NAME):$(AIRSTACK_IMAGE_TAG)

DOCKER_OPTS_CMD := sh -c "{ /etc/runit/2 &}; chpst -u $(USERNAME) bash"
DOCKER_OPTS_USER := --user $(USERNAME)
DOCKER_OPTS_USER_CONSOLE := --user root
DOCKER_OPTS_RUN := --detach
DOCKER_OPTS_RUN_CONSOLE := --rm -it
DOCKER_OPTS_BUILD := --rm
DOCKER_OPTS_COMMON := --publish-all --workdir /home/$(USERDIR) -e HOME=$(USERDIR) $(AIRSTACK_IMAGE_FULLNAME)
DOCKER_OPTS_LINUX := --volume $(CURR_DIR)/:/files/host/
DOCKER_OPTS_OSX := --volume $(ROOTDIR)/:/files/host/

ifeq ($(uname_S),Darwin)
	OS_SPECIFIC_RUNOPTS := $(DOCKER_OPTS_OSX)
else
	OS_SPECIFIC_RUNOPTS := $(DOCKER_OPTS_LINUX)
endif

# .PHONY should include all commands. Arrange in order that they appear in the Makefile
.PHONY: default all init \
	build build-all debug build-debug build-dev build-prod \
	clean clean-all clean-dev clean-prod \
	console console-debug console-dev console-prod \
	console-single console-single-dev console-single-prod \
	run run-debug run-dev run-prod \
	repair stats ps blank ssh \
	test test-all test-dev test-prod


################################################################################
# GENERAL COMMANDS
################################################################################

default: build

all:
	@echo all
	$(MAKE) build

bootstrap:
	@echo '========================================'
	@echo Already bootstrapped!
	@echo '========================================'
	$(MAKE) help

init:
	@echo init
	# @~/.airstack/bootstrap/init
	# empty template files
	# TODO: move all file related tasks to non PHONY tasks; no need to test if files exists since that's what make does by default
	$(foreach var,$(AIRSTACK_TEMPLATES_FILES),$(shell [ -e $(AIRSTACK_TEMPLATES_DIR)/$(var) ] || touch $(AIRSTACK_TEMPLATES_DIR)/$(var) ]))
	@[ -d $(TOP_DIR)$(AIRSTACK_CACHE_DIR) ] || mkdir -vp $(TOP_DIR)$(AIRSTACK_CACHE_DIR)
ifeq ($(uname_S),Darwin)
ifneq ($(shell boot2docker status),running)
	@boot2docker up
endif
export AIRSTACK_HOST=tcp://$(shell boot2docker ip 2>/dev/null):2375
endif

help:
	@echo TODO: add Makefile help
	# @echo USAGE:
	# @echo make build-dev
	# @echo make build-dev console-dev
	# @echo make -j5 build-all


################################################################################
# BUILD COMMANDS
#
# Commands for building containers.
################################################################################

build-all: build build-dev build-prod

build-tarball:
	tar -cvf $(AIRSTACK_CACHE_DIR)/$(AIRSTACK_IMAGE_NAME).$(AIRSTACK_IMAGE_TAG).tar -C $(TOP_DIR) -X $(AIRSTACK_AIRSTACKIGNORE) .

build-tarball-docker: build-tarball
	> $(AIRSTACK_CACHE_DIR)/Dockerfile.$(AIRSTACK_IMAGE_TAG)
	$(foreach var,$(AIRSTACK_TEMPLATES_FILES),cat $(AIRSTACK_TEMPLATES_DIR)/$(var) >> $(AIRSTACK_CACHE_DIR)/Dockerfile.$(AIRSTACK_IMAGE_TAG);)
	ln -f $(AIRSTACK_CACHE_DIR)/Dockerfile.$(AIRSTACK_IMAGE_TAG) $(AIRSTACK_CACHE_DIR)/Dockerfile
	tar -C $(TOP_DIR)/$(AIRSTACK_CACHE_DIR) --append --file=$(AIRSTACK_CACHE_DIR)/$(AIRSTACK_IMAGE_NAME).$(AIRSTACK_IMAGE_TAG).tar Dockerfile

build-docker: init build-tarball-docker
	docker build $(DOCKER_OPTS_BUILD) --tag airstack/$(AIRSTACK_IMAGE_NAME):$(AIRSTACK_IMAGE_TAG) - < $(AIRSTACK_CACHE_DIR)/$(AIRSTACK_IMAGE_NAME).$(AIRSTACK_IMAGE_TAG).tar

build: build-docker

build-debug:
	$(MAKE) DOCKER_OPTS_BUILD='--rm --no-cache' build

build-dev:
	$(MAKE) AIRSTACK_IMAGE_TAG=dev build

build-prod:
	$(MAKE) AIRSTACK_IMAGE_TAG=prod AIRSTACK_TEMPLATES_FILES="Dockerfile.core Dockerfile.packages Dockerfile.services Dockerfile.debug Dockerfile.tests" build


################################################################################
# CLEAN COMMANDS
#
# Commands for cleaning up leftover container build artifacts.
################################################################################

clean-all: clean clean-dev clean-prod

clean: init
	@echo "Removing docker image tree for $(AIRSTACK_IMAGE_FULLNAME) ..."
	docker rmi -f $(AIRSTACK_IMAGE_FULLNAME)

clean-dev:
	$(MAKE) AIRSTACK_IMAGE_TAG=dev clean

clean-prod:
	$(MAKE) AIRSTACK_IMAGE_TAG=prod clean


################################################################################
# CONSOLE COMMANDS
#
# Commands for running containers in a console window in foreground.
#
# The commands named console-single* will launch containers with
# only the remote /dev/log forwarder running on start
# Commands without *single* will run containers in multi mode, with
# all 'up' services running.
#
# CTRL-C Exits and does auto-cleanup.
################################################################################

console: init
	docker run $(DOCKER_OPTS_RUN_CONSOLE) $(OS_SPECIFIC_RUNOPTS) $(DOCKER_OPTS_USER_CONSOLE) $(DOCKER_OPTS_COMMON) $(DOCKER_OPTS_CMD)

debug: console-debug

console-debug:
	$(MAKE) DOCKER_OPTS_CMD='/bin/bash' console

console-dev:
	$(MAKE) AIRSTACK_IMAGE_TAG=dev console

console-prod:
	$(MAKE) AIRSTACK_IMAGE_TAG=prod console

console-single:
	$(MAKE) DOCKER_OPTS_CMD='sh -c "{ /etc/runit/2 single &}; chpst -u $(USERNAME) /bin/bash"' console

console-single-dev:
	$(MAKE) DOCKER_OPTS_CMD='sh -c "{ /etc/runit/2 single &}; chpst -u $(USERNAME) /bin/bash"' console-dev

console-single-prod:
	$(MAKE) DOCKER_OPTS_CMD='sh -c "{ /etc/runit/2 single &}; chpst -u $(USERNAME) /bin/bash"' console-prod


################################################################################
# RUN COMMANDS
#
# Commands for running containers in background.
#
# Outputs id of daemonized container
# To cleanup, run `docker rm <imageid>` after stopping container.
################################################################################

run: init
	docker run $(DOCKER_OPTS_RUN) $(OS_SPECIFIC_RUNOPTS) $(DOCKER_OPTS_USER) $(DOCKER_OPTS_COMMON) $(DOCKER_OPTS_CMD)

run-debug:
	$(MAKE) DOCKER_OPTS_RUN="--rm -it" run

run-dev:
	$(MAKE) AIRSTACK_IMAGE_TAG=dev run

run-prod:
	$(MAKE) AIRSTACK_IMAGE_TAG=prod run


################################################################################
# DOCKER COMMANDS
#
# Convenience helper commands for managing docker
################################################################################

repair: init
ifeq ($(uname_S),Darwin)
	@printf "\n\
	=====================\n\
	Repairing boot2docker\n\
	=====================\n\
	"
	@printf "\nTurning off existing boot2docker VMs..."
	@boot2docker poweroff
	@printf "DONE\n"

	@printf "\nRemoving existing boot2docker setup..."
	@boot2docker destroy
	@printf "DONE\n"

	@printf "\nInitializing new boot2docker setup..."
	boot2docker init > /dev/null
	@printf "DONE\n"
endif

stats:
	docker images | grep $(USERDIR)

ps:
	docker ps

blank:
	docker run --rm -it debian:jessie /bin/bash

ssh:
ifeq ($(uname_S),Darwin)
	boot2docker ssh
endif

################################################################################
# TEST COMMANDS
################################################################################

test-all: test test-dev test-prod

test:
	@echo test
	$(MAKE) DOCKER_OPTS_CMD="core-test-runner -f /package/airstack/test/*_spec.lua" console

test-dev:
	@echo test
	$(MAKE) AIRSTACK_IMAGE_TAG=dev test

test-prod:
	@echo test
	$(MAKE) AIRSTACK_IMAGE_TAG=prod test
