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

import Foundation
import Security

/// Descriptions contain no service, account, or secret values.
public enum SecretStoreError: Error, Equatable, Sendable, LocalizedError {
    case accessDenied
    case interactionNotAllowed
    case unavailable
    case invalidData
    case unexpectedStatus(OSStatus)

    init(status: OSStatus) {
        switch status {
        case errSecAuthFailed, errSecUserCanceled, errSecMissingEntitlement:
            self = .accessDenied
        case errSecInteractionNotAllowed:
            self = .interactionNotAllowed
        case errSecNotAvailable:
            self = .unavailable
        default:
            self = .unexpectedStatus(status)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "Keychain access was denied."
        case .interactionNotAllowed: return "Keychain interaction is not allowed."
        case .unavailable: return "The Keychain is unavailable."
        case .invalidData: return "The Keychain item is not valid UTF-8 secret data."
        case .unexpectedStatus(let status): return "Keychain operation failed (status \(status))."
        }
    }
}

public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "macpocketknife") {
        self.service = service
    }

    public func secret(for key: SecretKey) throws -> String? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return value
    }

    public func setSecret(_ value: String, for key: SecretKey) throws {
        // Keychain items cannot store empty data; an empty secret means removal.
        if value.isEmpty {
            try removeSecret(for: key)
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var item = query(for: key)
        item.merge(attributes) { _, new in new }
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query(for: key) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecretStoreError(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw SecretStoreError(status: status)
        }
    }

    public func removeSecret(for key: SecretKey) throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError(status: status)
        }
    }

    private func query(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
