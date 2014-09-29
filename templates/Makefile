# THIS MAKEFILE CAN BE COPIED INTO AN AIRSTACK IMAGE PROJECT

# Set variables here
# AIRSTACK_IMAGE_NAME := airstack/core
# AIRSTACK_BUILD_TEMPLATES_DIR := $(AIRSTACK_DIR)/config
# AIRSTACK_BUILD_TEMPLATES_PRODUCTION := Dockerfile.base Dockerfile.packages Dockerfile.services
# AIRSTACK_BUILD_TEMPLATES_DEVELOPMENT := Dockerfile.base Dockerfile.packages Dockerfile.packages.development Dockerfile.services Dockerfile.services.development Dockerfile.services.tests
# AIRSTACK_BUILD_TEMPLATES_TEST := $(AIRSTACK_BUILD_DEVELOPMENT)


################################################################################
# BOOTSTRAP MAKEFILE: DO NOT EDIT BELOW THIS LINE
AIRSTACK_HOME ?= ~/.airstack
ifeq ($(shell test -d $(AIRSTACK_HOME)/bootstrap && echo yes),yes)
include $(AIRSTACK_HOME)/bootstrap/Makefile
else
.PHONY: bootstrap
bootstrap:
  # TODO: maybe add -L if it's secure; better to use GPG and sign the install script
  curl -s https://raw.githubusercontent.com/airstack/bootstrap/master/install | sh -e
endif
