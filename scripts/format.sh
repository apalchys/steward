#!/bin/sh

set -e

mode="format"

if [ "$#" -gt 0 ]; then
    case "$1" in
        --check|--lint)
            mode="lint"
            shift
            ;;
    esac
fi

if [ "$mode" = "lint" ]; then
    if [ "$#" -gt 0 ]; then
        swift format lint --configuration .swift-format "$@"
    else
        swift format lint --configuration .swift-format --parallel --recursive Sources
    fi
else
    if [ "$#" -gt 0 ]; then
        swift format format --configuration .swift-format --in-place "$@"
    else
        swift format format --configuration .swift-format --in-place --parallel --recursive Sources
    fi
fi
