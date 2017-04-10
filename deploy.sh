#!/bin/bash
set -eu
hugo
cd public
git add -A
git commit -m "${1:-$(date -Iseconds)}"
git push origin master
