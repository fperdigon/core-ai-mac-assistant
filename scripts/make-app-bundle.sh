#!/bin/sh
# Copyright 2026 The Core AI Mac Assistant contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Run with: sh scripts/make-app-bundle.sh [Swift build options]
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
version=$(cat VERSION)
if ! printf '%s\n' "$version" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s\n' 'VERSION must contain a numeric major.minor.patch version.' >&2
    exit 1
fi

# Keep build diagnostics separate so stdout ends with the bundle path.
swift build -c release --arch arm64 --arch x86_64 "$@" >&2
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 "$@" --show-bin-path)
bundle="$root/build/Core AI Mac Assistant.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/CoreAIMacAssistant" "$bundle/Contents/MacOS/CoreAIMacAssistant"
chmod 755 "$bundle/Contents/MacOS/CoreAIMacAssistant"
sed "s/@VERSION@/$version/g" Resources/Info.plist > "$bundle/Contents/Info.plist"
plutil -lint "$bundle/Contents/Info.plist" >&2

identity=${SIGN_IDENTITY:--}
if [ "$identity" = '-' ]; then
    codesign --force --sign - --options runtime "$bundle" >&2
else
    codesign --force --sign "$identity" --options runtime --timestamp "$bundle" >&2
fi
codesign --verify --strict "$bundle" >&2
printf '%s\n' "$bundle"
