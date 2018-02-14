#!/bin/sh

#
# This script processes dSYM files for Release builds of your apps. dSYM files
# are needed to fully symbolicate crash reports from Release builds when using
# Kumulos's Crash Reporting features.
#
# It is intended to be used as part of a Run Script Phase in your app's Xcode
# project.
#
# Inside your Run Script phase, you should invoke this script as follows:
#
#   upload_dsyms.sh API_KEY SERVER_KEY
#
# You should replace the API_KEY and SERVER_KEY tokens with your Kumulos app's
# API key and server key respectively.
#

UPLOAD_URL="https://crash-symbolicator.app.delivery/dsyms"

if [ "Release" != "$CONFIGURATION" ]; then
    echo "[KUM] Not processing dSYM info for $CONFIGURATION builds"
    exit 0
fi

if [ "$1" != "upload" ]; then
    API_KEY="$1"
    SERVER_KEY="$2"

    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    SCRIPT="$(basename $0)"

    echo "[KUM] Starting dSYM processing in the background..."
    CMD="$DIR/$SCRIPT upload $API_KEY $SERVER_KEY"

    eval "$CMD" > /dev/null 2>&1 &
    exit 0
fi

API_KEY="$2"
SERVER_KEY="$3"

WORKDIR=$(mktemp -d -t kumulos)

if [ $? -ne 0 ]; then
    echo "Failed to create temp working directory"
    exit $?
fi

ZIPDIR="$WORKDIR/dSYMs"
ZIPFILE="$WORKDIR/upload.zip"

mkdir "$ZIPDIR"

if [ $? -ne 0 ]; then
    echo "Failed to create temp working directory"
    rm -rf "$WORKDIR"
    exit 1
fi

DSYMS=$(find "$BUILT_PRODUCTS_DIR" -iname "*.dSYM")

if [ $? -ne 0 ]; then
    echo "Failed to find dSYM files, aborting"
    exit $?
fi

while read -r DSYM; do
    cp -R "$DSYM" "$ZIPDIR/"

    if [ $? -ne 0 ]; then
        echo "Failed to copy $DSYM for processing"
        rm -rf "$WORKDIR"
        exit 1
    fi
done <<< "$DSYMS"

OLD_PWD="$PWD"

cd "$ZIPDIR" && zip -r "$ZIPFILE" .

if [ $? -ne 0 ]; then
    echo "Failed to create zip archive for upload"
    rm -rf "$WORKDIR"
    cd "$OLD_PWD"
    exit 1
fi

cd "$OLD_PWD"

CURL_MAJOR=$(curl --version | head -n 1 | cut -f 2 -d " " | cut -f 1 -d ".")
CURL_MINOR=$(curl --version | head -n 1 | cut -f 2 -d " " | cut -f 2 -d ".")

if [ $CURL_MAJOR -lt 7 ] && [ $CURL_MINOR -lt 52 ]; then
    curl --fail --retry 3 --retry-delay 3 --user "$API_KEY:$SERVER_KEY" -X PUT -F dsyms="@$ZIPFILE" "$UPLOAD_URL"
else
    curl --fail --retry 3 --retry-delay 3 --retry-connrefused --user "$API_KEY:$SERVER_KEY" -X PUT -F dsyms="@$ZIPFILE" "$UPLOAD_URL"
fi

if [ $? -ne 0 ]; then
    echo "Failed upload"
    rm -rf "$WORKDIR"
    exit 1
fi

rm -rf "$WORKDIR"
