#!/bin/bash

echo "Updating Sileo repo..."

cd repo

dpkg-scanpackages -m debs > Packages
gzip -kf Packages

cd ..

git add .
git commit -m "repo update"
git push

echo "Repo updated!"