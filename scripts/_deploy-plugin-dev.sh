#!/bin/bash

PLUGIN="net.localhost.streamdeck.clipboard-buddy.sdPlugin"

HERE=$(dirname "$0")

# Making sure the local version of the plugin is deployed
rsync -av "${HERE}/../Sources/${PLUGIN}" "/Users/${USER}/Library/Application Support/com.elgato.StreamDeck/Plugins/"
