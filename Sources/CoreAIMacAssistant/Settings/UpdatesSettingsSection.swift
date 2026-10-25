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

import CoreAIMacAssistantCore
import SwiftUI

@MainActor
struct UpdatesSettingsSection: View {
    @Binding var channel: UpdateChannel
    @Binding var automatically: Bool
    let checkNow: () -> Void

    var body: some View {
        Section("Updates") {
            Picker("Channel", selection: $channel) {
                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                    Text(channel.displayName).tag(channel)
                }
            }
            Text(channel == .stable ? "Tested releases." : "Latest builds; may be less tested.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Check for updates automatically", isOn: $automatically)
            Text("Checks at launch, at most once every 24 hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Check now", action: checkNow)
        }
    }
}
