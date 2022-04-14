#!/bin/sh

PROJ="Clipboard-Buddy"
HERE=$(dirname "$0")

# THIS SCRIPT IS JUST A SHORTCUT FOR LOCAL ITERATIVE TESTING (build, regroup code & deploy for testing)

# 1) BUILD
xcodebuild -project "${HERE}/../Sources/${PROJ}.xcodeproj" -alltargets -configuration Debug

# 2) CONSOLIDATE THE OPEN PLUGIN FOLDER
"${HERE}/_grab-build-for-dev.sh"

# 3) DEPLOY THE OPEN PLUGIN FOLDER
"${HERE}/_deploy-plugin-dev.sh"

# 4) RE-OPEN STREAM DECK TO LOAD THE LATEST VERSION OF THE PLUGIN
open "/Applications/Stream Deck.app"
