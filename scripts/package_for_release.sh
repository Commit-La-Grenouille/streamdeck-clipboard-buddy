#!/bin/bash

set -e

# Defining where we are
HERE=$(dirname "$0")

# Define the version we release
VERS=$1

if [ "${VERS}" = "" ];
then
    echo "You must provide a version as first argument !"
    exit 1
fi

# And some more data useful for this script
DTZ="DistributionToolMac.zip"
PLUGIN="net.localhost.streamdeck.clipboard-buddy"
EXT="streamDeckPlugin"


# Making sure we update the manifest.json with the right value
sed -e "s/\"Version\": \".*\",/\"Version\": \"${VERS}\",/" Sources/${PLUGIN}.sdPlugin/manifest.json > Sources/${PLUGIN}.sdPlugin/manifest.json.new
rm Sources/${PLUGIN}.sdPlugin/manifest.json
mv Sources/${PLUGIN}.sdPlugin/manifest.json.new Sources/${PLUGIN}.sdPlugin/manifest.json
git commit -am "[RELEASE] Bumping manifest.json version to ${VERS}"


# Grabbing the distribution tool if not yet present

#https://developer.elgato.com/documentation/stream-deck/sdk/packaging/
if [[ ! -e "${HERE}/DistributionTool" ]]; then

    curl -o "${HERE}/${DTZ}" "https://developer.elgato.com/documentation/stream-deck/distributiontool/${DTZ}"
    unzip "${HERE}/${DTZ}" -d "${HERE}"
    rm "${HERE}/${DTZ}"
fi

if [ -e  "${HERE}/../${PLUGIN}.${EXT}" ];
then
    echo "Unable to release ${PLUGIN}.${EXT} as such release already exists on the disk !"
    exit 1
fi

# Running the distribution tool to transform our open-plugin folder into a proper plugin archive
"${HERE}/DistributionTool" -b -i "Sources/${PLUGIN}.sdPlugin" -o "${HERE}/.."

# Then moving the release out of the way by renaming it with the version we will tag
git tag "${VERS}"
mv "${HERE}/../${PLUGIN}.${EXT}" "${HERE}/../${PLUGIN}.v${VERS}.${EXT}"
