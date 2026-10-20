#! /bin/sh

# The native scanner CI has a separate mandatory lint job. Do not rebuild the
# formatter inside Xcode as well; source formatting is already checked there.
if [ "${CI:-}" = "true" ] && [ "${PLATE_SCANNER_CI_SKIP_FORMAT:-0}" = "1" ]; then
    echo "Skipping duplicate formatter build; the dedicated lint check remains required."
    exit 0
fi

# Check if the folder name is exactly "LoopFollow"
FOLDER_NAME=$(basename "${SRCROOT}")
if [ "${FOLDER_NAME}" != "LoopFollow" ]; then
    echo "Skipping swiftformat: This script only runs in the LoopFollow directory, not in '${FOLDER_NAME}'"
    exit 0
fi

function assertEnvironment {
	if [ -z $1 ]; then 
		echo $2
		exit 127
	fi
}

assertEnvironment "${SRCROOT}" "Please set SRCROOT to project root folder"

unset SDKROOT

swift run -c release --package-path BuildTools swiftformat "${SRCROOT}" \
--header "LoopFollow\n{file}" \
--exclude Pods,Generated,R.generated.swift,fastlane/swift,Dependencies,dexcom-share-client-swift
