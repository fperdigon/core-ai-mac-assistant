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

import Foundation

public enum AssertionParser {
    public static func parse(
        _ assertionsByProcess: [NSNumber: [[String: Any]]],
        processName: (Int32) -> String?
    ) -> [SleepAssertion] {
        let sleepTypes: Set<String> = [
            "PreventUserIdleSystemSleep",
            "PreventSystemSleep",
            "PreventUserIdleDisplaySleep",
            "NoIdleSleepAssertion",
            "NoDisplaySleepAssertion",
            "PreventDiskIdle",
        ]
        var assertions: [SleepAssertion] = []

        for (pidNumber, entries) in assertionsByProcess {
            let pid = pidNumber.int32Value
            for entry in entries {
                guard let type = entry["AssertType"] as? String,
                      sleepTypes.contains(type) else {
                    continue
                }
                if let level = entry["AssertLevel"], (level as? NSNumber)?.intValue == 0 {
                    continue
                }
                let entryProcessName = entry["Process Name"] as? String
                let owner = entryProcessName.flatMap { $0.isEmpty ? nil : $0 }
                    ?? processName(pid)
                    ?? "unknown"
                assertions.append(SleepAssertion(
                    pid: pid,
                    processName: owner,
                    type: type,
                    name: entry["AssertName"] as? String ?? ""
                ))
            }
        }

        return assertions.sorted {
            if $0.pid != $1.pid { return $0.pid < $1.pid }
            if $0.type != $1.type { return $0.type < $1.type }
            return $0.name < $1.name
        }
    }
}
