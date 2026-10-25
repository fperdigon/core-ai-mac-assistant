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

import Darwin

public struct SysctlProcessTable: ProcessTableProviding {
    public init() {}

    public func snapshot(of pid: Int32) -> ProcessSnapshot? {
        guard pid > 0 else { return nil }
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let status = query.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, UInt32($0.count), &info, &size, nil, 0)
        }
        guard status == 0, size == MemoryLayout<kinfo_proc>.size,
              info.kp_proc.p_pid == pid else {
            return nil
        }

        // proc_name preserves longer names than the fixed-width p_comm field.
        var buffer = [UInt8](repeating: 0, count: 1024)
        let length = buffer.withUnsafeMutableBytes {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        let name: String
        if length > 0 {
            name = String(decoding: buffer.prefix(Int(length)).prefix { $0 != 0 }, as: UTF8.self)
        } else {
            name = withUnsafeBytes(of: info.kp_proc.p_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        // Darwin defines NODEV as (dev_t)(-1); Swift cannot import that macro.
        let noDevice = dev_t(-1)
        return ProcessSnapshot(
            pid: pid,
            parentPID: info.kp_eproc.e_ppid,
            name: name,
            hasControllingTerminal: info.kp_eproc.e_tdev != noDevice
        )
    }
}
