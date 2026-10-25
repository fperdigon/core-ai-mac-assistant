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
import Security
import Testing
@testable import CoreAIMacAssistantCore

private func checkSecretStore(_ store: any SecretStore) throws {
    #expect(try store.secret(for: .telegramBotToken) == nil)
    try store.removeSecret(for: .telegramBotToken)
    try store.setSecret("test value", for: .telegramBotToken)
    #expect(try store.secret(for: .telegramBotToken) == "test value")
    try store.setSecret("updated value 🔒", for: .telegramBotToken)
    #expect(try store.secret(for: .telegramBotToken) == "updated value 🔒")
    try store.setSecret("", for: .telegramBotToken)
    #expect(try store.secret(for: .telegramBotToken) == nil)
    try store.removeSecret(for: .telegramBotToken)
    #expect(try store.secret(for: .telegramBotToken) == nil)
    try store.removeSecret(for: .telegramBotToken)
}

@Test func inMemorySecretStoreRoundTripsAndRemoves() throws {
    try checkSecretStore(InMemorySecretStore())
}

@Test func inMemorySecretStoresAreIndependent() throws {
    let first = InMemorySecretStore()
    let second = InMemorySecretStore()
    try first.setSecret("test value", for: .telegramBotToken)
    #expect(try second.secret(for: .telegramBotToken) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
func keychainSecretStoreRoundTripsAndRemoves() throws {
    let service = "core-ai-mac-assistant.tests." + UUID().uuidString
    let store = KeychainSecretStore(service: service)
    defer {
        do {
            try store.removeSecret(for: .telegramBotToken)
        } catch {
            Issue.record(error)
        }
    }
    try checkSecretStore(store)
    try store.setSecret("persisted test value", for: .telegramBotToken)
    let reopened = KeychainSecretStore(service: service)
    #expect(try reopened.secret(for: .telegramBotToken) == "persisted test value")
    let other = KeychainSecretStore(service: service + ".other")
    #expect(try other.secret(for: .telegramBotToken) == nil)
}

@Test func keychainErrorsHaveTypedSafeDescriptions() {
    #expect(SecretStoreError(status: errSecAuthFailed) == .accessDenied)
    #expect(SecretStoreError(status: errSecInteractionNotAllowed) == .interactionNotAllowed)
    #expect(SecretStoreError(status: errSecNotAvailable) == .unavailable)
    #expect(SecretStoreError(status: errSecParam) == .unexpectedStatus(errSecParam))
    #expect(SecretStoreError.invalidData.errorDescription != nil)
    #expect(SecretStoreError.accessDenied.errorDescription == "Keychain access was denied.")
}
