#!/bin/sh
# Copyright 2026 Francisco Perdigon Romero and contributors
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

# Check tracked working-tree Swift files; untracked files are outside the scope.
# Requires Git and standard POSIX utilities, with no additional dependencies.
set -eu
LC_ALL=C
export LC_ALL

root=$(git rev-parse --show-toplevel) || exit 2
cd "$root"
expected=$(cat <<'HEADER'
// Copyright 2026 Francisco Perdigon Romero and contributors
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
)
# Git quotes unusual filenames. Such entries fail closed rather than being skipped.
files=$(git ls-files -- 'Sources/*.swift' 'Tests/*.swift') || exit 2
[ -n "$files" ] || exit 0
printf '%s\n' "$files" | while IFS= read -r file; do
    if [ ! -f "$file" ]; then
        printf '%s\n' 'Cannot read a tracked Swift file for license checking.' >&2
        exit 1
    fi
    actual=$(sed -n '1,13p' "$file") || exit 2
    if [ "$actual" != "$expected" ]; then
        printf '%s\n' "Missing or incorrect Apache-2.0 header: $file" >&2
        exit 1
    fi
done
