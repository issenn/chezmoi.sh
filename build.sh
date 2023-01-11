#!/usr/bin/env zsh
# shellcheck shell=bash


# -e: exit on error
# -u: exit on unset variables
set -eu

cp -f chezmoi.sh bin/chezmoi
chmod +x bin/chezmoi
