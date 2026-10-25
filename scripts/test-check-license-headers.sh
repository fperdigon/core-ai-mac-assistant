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

# Run with: sh scripts/test-check-license-headers.sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' 0
trap 'exit 1' HUP INT TERM
mkdir -p "$test_root/scripts" "$test_root/Sources/Example" "$test_root/Tests/ExampleTests"
cp "$script_dir/check-license-headers.sh" "$test_root/scripts/check-license-headers.sh"
cd "$test_root"
git init -q

scan() {
    sh scripts/check-license-headers.sh
}

expect_rejection() {
    result=0
    scan > scan-output 2>&1 || result=$?
    if [ "$result" -ne 1 ]; then
        printf '%s\n' 'Expected a missing or incorrect license header to be rejected.' >&2
        exit 1
    fi
}

cat > header <<'HEADER'
// Copyright 2026 The Core AI Mac Assistant contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
HEADER
scan # A repository with no tracked Swift files passes.
printf '%s\n' 'struct Example {}' > 'Sources/Example/Example File.swift'
scan # Untracked files are ignored.
git add 'Sources/Example/Example File.swift'
expect_rejection
cat header > 'Sources/Example/Example File.swift'
printf '\n%s\n' 'struct Example {}' >> 'Sources/Example/Example File.swift'
scan # Tracked working-tree contents are checked, including unstaged fixes.

printf '%s\n' 'import Testing' > Tests/ExampleTests/ExampleTests.swift
git add Tests
expect_rejection
cat header > Tests/ExampleTests/ExampleTests.swift
printf '\n%s\n' 'import Testing' >> Tests/ExampleTests/ExampleTests.swift
scan

# A partial header, or a full header after code, must not pass.
sed -n '1,12p' header > Tests/ExampleTests/ExampleTests.swift
expect_rejection
printf '%s\n' 'import Testing' > Tests/ExampleTests/ExampleTests.swift
cat header >> Tests/ExampleTests/ExampleTests.swift
expect_rejection
cat header > Tests/ExampleTests/ExampleTests.swift

# Swift files outside Sources and Tests, and non-Swift files, are out of scope.
printf '%s\n' '// No header required here.' > Example.swift
printf '%s\n' 'Example text.' > Sources/Example/notes.txt
git add Example.swift Sources/Example/notes.txt
scan
# Invocation from a subdirectory must still check the whole repository.
(cd Tests && sh ../scripts/check-license-headers.sh)
printf '%s\n' 'License header checker tests passed.'
