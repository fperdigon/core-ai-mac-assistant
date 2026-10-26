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

public struct TelegramChannel: Sendable {
    private let client: any TelegramServing
    private let formatter: any TelegramAlertFormatting
    private let chatID: Int64
    private let includeMachineName: String?

    public init(
        client: any TelegramServing, chatID: Int64,
        formatter: any TelegramAlertFormatting = TelegramAlertFormatter(),
        includeMachineName: String? = nil
    ) {
        self.client = client
        self.chatID = chatID
        self.formatter = formatter
        self.includeMachineName = includeMachineName
    }

    public func send(notice: Notice, silent: Bool = false) async throws {
        let machine = includeMachineName.map { " (\($0))" } ?? ""
        try await client.sendMessage(
            chatID: chatID, text: "\(notice.title)\(machine)\n\(notice.body)", silent: silent
        )
    }

    public func send(
        alert: BatteryAlert, blockers: [String]? = nil, silent: Bool = false,
        estimate: BatteryEstimate = BatteryEstimate()
    ) async throws {
        let text = formatter.format(
            alert: alert, blockers: blockers, includeMachineName: includeMachineName, estimate: estimate
        )
        try await client.sendMessage(chatID: chatID, text: text, silent: silent)
    }
}
