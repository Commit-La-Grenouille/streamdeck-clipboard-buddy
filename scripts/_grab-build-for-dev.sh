#!/bin/bash

HERE=$(dirname "$0")

PNAME="Clipboard-Buddy"
PLUGIN="net.localhost.streamdeck.clipboard-buddy.sdPlugin"

# When building with the XCode UI, it goes into these convoluted folders
XCODE_TMP="/Users/${USER}/Library/Developer/Xcode/DerivedData"
XCODE_SUB="Build/Products/Debug"

# When using the commandline build, it goes into a more simpler folder
XCODE_CLI_PATH="${HERE}/../Sources/build/Debug"


#
# Checking if we did a commandline build
#
if [ -e "${XCODE_CLI_PATH}/${PNAME}" ]; then
    mv -v "${XCODE_CLI_PATH}/${PNAME}" "${HERE}/../Sources/${PLUGIN}/"
else
    # Making sure we target the latest build folder
    XCODE_FOLDER=$(ls -1 "${XCODE_TMP}" | grep "${PNAME}" | head -n 1)

    # Moving the freshly built binary into the open-folder plugin
    mv -v "${XCODE_TMP}/${XCODE_FOLDER}/${XCODE_SUB}/${PNAME}" "${HERE}/../Sources/${PLUGIN}/"
fi
