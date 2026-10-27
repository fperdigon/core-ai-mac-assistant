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

import Carbon
import Foundation

@MainActor
final class GlobalHotkey {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (@MainActor () -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(enabled: Bool, key: String) -> Bool {
        unregister()
        guard enabled else { return true }
        guard handler != nil, let code = Self.keyCodes[key] else { return false }
        let identifier = EventHotKeyID(signature: 0x4D504B44, id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        return RegisterEventHotKey(code, modifiers, identifier, GetApplicationEventTarget(), 0, &hotkey) == noErr
    }

    func unregister() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
    }

    func shutdown() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        action = nil
    }

    // Carbon virtual key codes refer to physical ANSI letter keys.
    private static let keyCodes: [String: UInt32] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5,
        "H": 4, "I": 34, "J": 38, "K": 40, "L": 37, "M": 46,
        "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1,
        "T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6,
    ]
}
