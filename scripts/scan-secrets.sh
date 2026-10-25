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

# Scan tracked working-tree contents, including staged new files, without printing secrets.
set -eu
LC_ALL=C
export LC_ALL

root=$(git rev-parse --show-toplevel) || exit 2
cd "$root"
allowlist=scripts/secret-allowlist.txt
if [ ! -f "$allowlist" ]; then
    printf '%s\n' 'Secret scanner allowlist is missing.' >&2
    exit 2
fi

pattern='[0-9]{5,}:[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]+=*|-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----'
status=0
matches=$(git grep --no-ext-grep --no-textconv -a -h -o -i -E "$pattern" -- . ':!scripts/scan-secrets.sh') || status=$?
case "$status" in
    0) ;;
    1) exit 0 ;;
    *) printf '%s\n' 'Secret scanner could not read tracked files.' >&2; exit 2 ;;
esac

# Entries are complete, case-sensitive matched values, never patterns or whole-line exclusions.
if printf '%s\n' "$matches" | awk '
    FILENAME == ARGV[1] {
        if ($0 != "" && $0 !~ /^#/) allowed[$0] = 1
        next
    }
    !($0 in allowed) { found = 1 }
    END { exit found ? 1 : 0 }
' "$allowlist" -; then
    exit 0
fi
printf '%s\n' 'Potential secret detected in tracked files. Remove it or explicitly allowlist an exact fake placeholder.' >&2
exit 1
