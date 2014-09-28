#######################################
# VARIABLES
#
# Set these at runtime to override the below defaults.
# e.g.:
# `make AIRSTACK_CMD=/bin/bash console`
# `make AIRSTACK_USERNAME=root AIRSTACK_CMD=/bin/bash run`
# `make AIRSTACK_IMAGE_TAG=1.2-debug build`
# `make AIRSTACK_ENV=development build`
#######################################

DEBUG ?= false
ifneq ($(DEBUG),false)
	DEBUG := true
endif

ifeq ($(DEBUG),true)
	SHELL := /bin/sh -xv
else
	SHELL := /bin/sh
endif

# Name of current working dir parent; ex: 'bootstrap'
PARENT_DIR := $(notdir $(patsubst %/,%,$(dir $(CURDIR))))

AIRSTACK_ENV_DEVELOPMENT ?= development
AIRSTACK_ENV_TEST ?= test
AIRSTACK_ENV_PRODUCTION ?= production


################################################################################
# COMMONLY OVERRIDDEN VARS
################################################################################

# Relative path to airstack dir; for cache, configs, etc.
AIRSTACK_DIR ?= .airstack

# Name of Docker image to build; ex: airstack/core
AIRSTACK_IMAGE_NAME ?= $(PARENT_DIR)

# Current build environment: ex: development, test, production
AIRSTACK_ENV ?= $(AIRSTACK_ENV_DEVELOPMENT)

# Docker image tag; ex: development
AIRSTACK_IMAGE_TAG ?= $(AIRSTACK_ENV)

# Build file templates located in AIRSTACK_TEMPLATES_DIR.
# Concatenated together on build. Useful for customizing dev vs test vs prod builds.
AIRSTACK_BUILD_TEMPLATES_PRODUCTION ?= Dockerfile.base Dockerfile.packages Dockerfile.services
AIRSTACK_BUILD_TEMPLATES_DEVELOPMENT ?= $(AIRSTACK_BUILD_TEMPLATES_PRODUCTION) Dockerfile.development
AIRSTACK_BUILD_TEMPLATES_TEST ?= $(AIRSTACK_BUILD_TEMPLATES_PRODUCTION) Dockerfile.test

AIRSTACK_BUILD_TEMPLATES ?= $(AIRSTACK_BUILD_TEMPLATES_$(AIRSTACK_ENV))


################################################################################
# CONFIG VARS
################################################################################
AIRSTACK_USERNAME ?= airstack
AIRSTACK_USERDIR ?= $(AIRSTACK_USERNAME)

AIRSTACK_TEMPLATES_DIR ?= $(AIRSTACK_DIR)/templates
AIRSTACK_CACHE_DIR ?= $(AIRSTACK_DIR)/cache
AIRSTACK_IGNOREFILE ?= $(AIRSTACK_DIR)/.airstackignore

AIRSTACK_IMAGE_FULLNAME ?= $(AIRSTACK_IMAGE_NAME):$(AIRSTACK_IMAGE_TAG)

AIRSTACK_RUN_MODE ?= multi
AIRSTACK_CMD ?= sh -c '{ /etc/runit/2 $(AIRSTACK_RUN_MODE) &}'
# TODO: John, why do we need chpst here? It doesn't seem to work since the Docker user is airstack
# AIRSTACK_SHELL ?= chpst -u $(AIRSTACK_USERNAME) /bin/rbash
# TODO: should we use rbash or bash?
AIRSTACK_SHELL ?= /bin/rbash
AIRSTACK_CMD_CONSOLE ?= sh -c '{ /etc/runit/2 $(AIRSTACK_RUN_MODE) &}; $(AIRSTACK_SHELL)'

AIRSTACK_BASE_IMAGE := debian:jessie

DOCKER_OPTS_USER ?= --user $(AIRSTACK_USERNAME)
DOCKER_OPTS_RUN ?= --detach
DOCKER_OPTS_RUN_CONSOLE ?= --rm -it
DOCKER_OPTS_BUILD ?= --rm
DOCKER_OPTS_COMMON ?= --publish-all --workdir /home/$(AIRSTACK_USERDIR) -e HOME=$(AIRSTACK_USERDIR) $(AIRSTACK_IMAGE_FULLNAME)

# TODO: remove auto mounting of host files; CLI handles mounting
# DOCKER_OPTS_LINUX ?= --volume $(CURR_DIR)/:/files/host/
# DOCKER_OPTS_OSX ?= --volume $(ROOTDIR)/:/files/host/

# Replace / and \ and spaces with underscores
IMAGE_TAG_FILENAME := $(shell echo $(AIRSTACK_IMAGE_TAG) | sed -e 's/[\/ \\]/_/g')

# TODO: only expand var if first char is not a '/'
AIRSTACK_CACHE_DIR := $(CURDIR)/$(AIRSTACK_CACHE_DIR)

PLATFORM := $(shell [ $$(uname -s 2>/dev/null) = Darwin ] && echo osx || echo linux)
ifeq ($(PLATFORM),osx)
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

all: build-all

bootstrap:
	@echo '========================================'
	@echo Already bootstrapped!
	@echo '========================================'
	@$(MAKE) help

init:
	@# TODO: move all file related tasks to non PHONY tasks; no need to test if files exists since that's what make does by default
	$(foreach var,$(AIRSTACK_BUILD_TEMPLATES),$(shell [ -e $(AIRSTACK_TEMPLATES_DIR)/$(var) ] || touch $(AIRSTACK_TEMPLATES_DIR)/$(var) ]))
	@[ -d $(AIRSTACK_CACHE_DIR) ] || mkdir -vp $(AIRSTACK_CACHE_DIR)
	@# TODO: add call to ~/.airstack/bootstrap/init to populate .airstackignore ???
	@# TODO: split boot2docker commands into separate init ???
ifeq ($(PLATFORM),osx)
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

build-all: build-development build-test build-production

build: build-development

# Rebuild dev image without using the cache
build-debug:
	@$(MAKE) DOCKER_OPTS_BUILD='--rm --no-cache' build-development

build-dev: build-development
build-development:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) AIRSTACK_BUILD_TEMPLATES="$(AIRSTACK_BUILD_TEMPLATES_DEVELOPMENT)" build-image

build-test:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) AIRSTACK_BUILD_TEMPLATES="$(AIRSTACK_BUILD_TEMPLATES_TEST)" build-image

build-prod: build-production
build-production:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) AIRSTACK_BUILD_TEMPLATES="$(AIRSTACK_BUILD_TEMPLATES_PRODUCTION)" build-image


################################################################################
# BUILD HELPERS
################################################################################

build-tarball:
	tar -cvf $(AIRSTACK_CACHE_DIR)/build.$(IMAGE_TAG_FILENAME).tar -C $(CURDIR) -X $(AIRSTACK_IGNOREFILE) .

build-tarball-docker: build-tarball
	> $(AIRSTACK_CACHE_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME)
	$(foreach var,$(AIRSTACK_BUILD_TEMPLATES),cat $(AIRSTACK_TEMPLATES_DIR)/$(var) >> $(AIRSTACK_CACHE_DIR)/Dockerfile.$(IMAGE_TAG_FILENAME);)
	tar -C $(AIRSTACK_CACHE_DIR) --append -s /Dockerfile.$(IMAGE_TAG_FILENAME)/Dockerfile/ --file=$(AIRSTACK_CACHE_DIR)/build.$(IMAGE_TAG_FILENAME).tar Dockerfile.$(IMAGE_TAG_FILENAME)

build-docker: init build-tarball-docker
	docker build $(DOCKER_OPTS_BUILD) --tag $(AIRSTACK_IMAGE_FULLNAME) - < $(AIRSTACK_CACHE_DIR)/build.$(IMAGE_TAG_FILENAME).tar

build-image: build-docker


################################################################################
# CLEAN COMMANDS
#
# Commands for cleaning up leftover container build artifacts.
################################################################################

clean: clean-all
clean-all: clean-development clean-test clean-production clean-cache

clean-tag: init
	@echo "Removing docker image tree for $(AIRSTACK_IMAGE_FULLNAME) ..."
	! docker rmi -f $(AIRSTACK_IMAGE_FULLNAME)

clean-dev: clean-development
clean-development:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) clean-tag

clean-test:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) clean-tag

clean-prod: clean-production
clean-production:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) clean-tag

clean-cache:
ifeq ($(CURDIR),$(findstring $(CURDIR)a,$(AIRSTACK_CACHE_DIR)))
	rm -rf $(AIRSTACK_CACHE_DIR)
else
	@printf "\n[WARNING] Not deleting cache directory\n\n"
endif

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

console:
	@$(MAKE) DOCKER_OPTS_RUN="$(DOCKER_OPTS_RUN_CONSOLE)" AIRSTACK_CMD="$(AIRSTACK_CMD_CONSOLE)" run

# Run console without starting any services
debug: console-debug
console-debug:
	@$(MAKE) AIRSTACK_CMD_CONSOLE="$(AIRSTACK_SHELL)" console

console-dev: console-development
console-development:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) console

console-test:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) console

console-prod: console-prodution
console-prodution:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) console

console-single:
	@$(MAKE) AIRSTACK_RUN_MODE=single console


################################################################################
# RUN COMMANDS
#
# Commands for running containers in background.
#
# Outputs id of daemonized container
# To cleanup, run `docker rm <imageid>` after stopping container.
################################################################################

run: init
	docker run $(DOCKER_OPTS_RUN) $(OS_SPECIFIC_RUNOPTS) $(DOCKER_OPTS_USER) $(DOCKER_OPTS_COMMON) $(AIRSTACK_CMD)

run-dev: run-development
run-development:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) run

run-test:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) run

run-dev: run-production
run-production:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) run

run-base: init
	docker run --rm -it $(AIRSTACK_BASE_IMAGE) /bin/bash


################################################################################
# TEST COMMANDS
################################################################################

test-all: test test-development test-production

test-runner:
	@echo test-runner
	@$(MAKE) AIRSTACK_CMD_CONSOLE="core-test-runner -f /package/airstack/test/*_spec.lua" console

test:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_TEST) test-runner

test-dev: test-development
test-development:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_DEVELOPMENT) test-runner

test-prod: test-production
test-production:
	@$(MAKE) AIRSTACK_ENV=$(AIRSTACK_ENV_PRODUCTION) test-runner


################################################################################
# DOCKER COMMANDS
#
# Convenience helper commands for managing docker
################################################################################

repair: init
ifeq ($(PLATFORM),osx)
	@printf "\n\
	=====================\n\
	Repairing boot2docker\n\
	=====================\n\
	"
	@ehco "\nTurning off existing boot2docker VMs..."
	@boot2docker poweroff
	@echo "DONE\n"

	@echo "\nRemoving existing boot2docker setup..."
	@boot2docker destroy
	@echo "DONE\n"

	@echo "\nInitializing new boot2docker setup..."
	boot2docker init > /dev/null
	@echo "DONE\n"
endif

stats: init
	docker images | grep $(AIRSTACK_IMAGE_NAME)

ps: init
	docker ps

ssh-vm: init
ifeq ($(PLATFORM),osx)
	boot2docker ssh
endif
