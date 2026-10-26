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

import Darwin
import Foundation
import IOKit.pwr_mgt

public struct IOKitAssertionProvider: AssertionProviding {
    public init() {}

    public func currentAssertions() -> [SleepAssertion] {
        var result: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&result)
        let dictionary = result?.takeRetainedValue()
        guard status == kIOReturnSuccess,
              let assertionsByProcess = dictionary as? [NSNumber: [[String: Any]]] else {
            return []
        }

        return AssertionParser.parse(assertionsByProcess, processName: Self.processName)
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let length = buffer.withUnsafeMutableBytes {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).prefix { $0 != 0 }, as: UTF8.self)
    }
}
