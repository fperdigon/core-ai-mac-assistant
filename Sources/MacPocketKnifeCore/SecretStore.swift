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

public enum SecretKey: String, Sendable {
    case telegramBotToken
}

public protocol SecretStore: Sendable {
    func secret(for key: SecretKey) throws -> String?
    /// Setting an empty string removes the secret.
    func setSecret(_ value: String, for key: SecretKey) throws
    /// Removing a missing secret succeeds.
    func removeSecret(for key: SecretKey) throws
}
