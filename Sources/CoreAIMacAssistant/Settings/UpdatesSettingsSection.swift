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
        Section {
            LabeledContent("Channel") {
                Picker("", selection: $channel) {
                    Text("Stable").tag(UpdateChannel.stable)
                    Text("Nightly").tag(UpdateChannel.nightly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }
            Text(channel == .stable
                 ? "Tagged releases (v0.1.x, ...): tested and announced."
                 : "A build of every change merged to main: newest features, less tested.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Automatic") {
                Toggle("Check once a day", isOn: $automatically)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent("Running") {
                Text("Core AI Mac Assistant \(BuildInfo.current.displayVersion)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent(" ") {
                Button("Check for updates…", action: checkNow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Software updates")
        }
    }
}
