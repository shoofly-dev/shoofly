#!/bin/bash
# Shoofly deploy script — bumps asset version and pushes to gh-pages
set -e
VERSION=$(date +%Y%m%d%H%M)
# Update version in index.html
sed -i '' "s/?v=[0-9]\{12\}/?v=$VERSION/g" index.html
echo "Asset version bumped to $VERSION"
git add index.html
git commit -m "deploy: cache bust v$VERSION" --allow-empty
git push origin main
git push origin main:gh-pages --force
echo "Deployed to shoofly.dev"
