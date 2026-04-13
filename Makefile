SHELL := /bin/bash

ICON_SOURCE ?= Assets/icon.png

.PHONY: fmt build test icon dmg

fmt:
	sh Scripts/format.sh

build:
	sh Scripts/build.sh

test:
	swift test

icon:
	sh Scripts/create_icon.sh "$(ICON_SOURCE)"

dmg:
	sh Scripts/create_dmg.sh
