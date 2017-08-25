#!/bin/bash
set -eu
git -C public clean -xfd
hugo --buildDrafts
cd public
git add -A
git commit --amend -m 'init'
git push -f origin master
