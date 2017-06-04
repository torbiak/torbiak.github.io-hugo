#!/bin/bash
set -eu
hugo
cd public
git add -A
git commit --amend -m 'init'
git push -f origin master
