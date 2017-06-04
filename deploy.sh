#!/bin/bash
set -eu
hugo --buildDrafts
cd public
git add -A
git commit --amend -m 'init'
git push -f origin master
