SHELL := /bin/bash

ICON_SOURCE ?= Assets/icon.png

.PHONY: fmt build icon

fmt:
	sh scripts/format.sh

build:
	sh scripts/build_app.sh

icon:
	sh scripts/create_icon.sh "$(ICON_SOURCE)"
