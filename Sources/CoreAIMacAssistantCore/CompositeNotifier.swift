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

public struct CompositeNotifier: AlertNotifying {
    private let channels: [any AlertNotifying]

    public init(channels: [any AlertNotifying]) {
        self.channels = channels
    }

    public func deliver(_ notice: Notice) async {
        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask { await channel.deliver(notice) }
            }
        }
    }
}
