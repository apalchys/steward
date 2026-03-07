SHELL := /bin/bash

ICON_SOURCE ?= Assets/icon.png

.PHONY: fmt build test icon

fmt:
	sh scripts/format.sh

build:
	sh scripts/build_app.sh

test:
	swift test

icon:
	sh scripts/create_icon.sh "$(ICON_SOURCE)"
