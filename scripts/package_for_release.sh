#!/bin/bash

set -e

# Defining where we are
HERE=$(dirname "$0")

# And some more data useful for this script
DTZ="DistributionToolMac.zip"
PLUGIN="net.localhost.streamdeck.clipboard-buddy.sdPlugin"


# Grabbingt the distribution tool if not yet present

#https://developer.elgato.com/documentation/stream-deck/sdk/packaging/
if [[ ! -e "${HERE}/DistributionTool" ]]; then

    curl -o "${HERE}/${DTZ}" "https://developer.elgato.com/documentation/stream-deck/distributiontool/${DTZ}"
    unzip "${HERE}/${DTZ}" -d "${HERE}"
    rm "${HERE}/${DTZ}"
fi

# Running the distribution tool to transform our open-plugin folder into a proper plugin archive
"${HERE}/DistributionTool" -b -i "Sources/${PLUGIN}" -o "${HERE}/.."
