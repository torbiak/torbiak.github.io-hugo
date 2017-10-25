#!/bin/bash
set -eu
desc=$(git log -n 1 --format='%h: %s')
git -C public clean -xfd
hugo --buildDrafts
cd public
git add -A
git commit --amend -m "$desc"
git push -f origin master
