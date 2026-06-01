#!/bin/bash

# This script will bump the version in all the "authoritative" places.
# Test output should no longer care about this, but run `make test` afterward to make sure
# Usage: ./bump-version.sh 1.2.3

set -euo pipefail
cd "$(dirname "$0")/.."

FULL_VERSION="$1"
MAJOR_VERSION=$(echo "$FULL_VERSION" | cut -f1 -d.)
MINOR_VERSION=$(echo "$FULL_VERSION" | cut -f2 -d.)

sed -Ei "s|^VERSION=.+|VERSION=$FULL_VERSION|" src/Makefile
sed -Ei "s|^VER_MAJOR=.+|VER_MAJOR=$MAJOR_VERSION|" src/Makefile
sed -Ei "s|^VER_MINOR=.+|VER_MINOR=$MINOR_VERSION|" src/Makefile
sed -Ei "s|^VERSION=.+|VERSION=$FULL_VERSION|" src/6502/Makefile

sed -Ei "s|VER_MAJOR:.+|VER_MAJOR:	$MAJOR_VERSION,|" src/js/engine.js
sed -Ei "s|VER_MINOR:.+|VER_MINOR:	$MINOR_VERSION,|" src/js/engine.js

sed -Ei "s|web interpreter v.+|web interpreter v$FULL_VERSION</a>|" src/js/webfrontend.html
sed -Ei "s|const VERSION = .+|const VERSION = \"$FULL_VERSION\";|" src/js/nodefrontend.js
