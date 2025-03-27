//
//  UnsafeBufferPointer+unprotected.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Common
import Foundation
import os.log

extension UnsafeBufferPointer {

    struct MemoryProtectionFailure: LocalizedError {
        let bufferDescr: String
        let code: Int32

        var errorDescription: String? {
            String("mprotect failed to set PROT_READ | PROT_WRITE for \(bufferDescr) with \(code)")
        }
    }

    /// Temporarily removes memory protection from the buffer (if needed) and calls the callback with the readable/writable memory buffer.
    /// Memory protection is restored to the original state afterwards.
    /// - Returns: Generic callback result.
    /// - Throws: `MemoryProtectionFailure` error if the memory protection change fails.
    func withTemporaryUnprotectedMemory<Result>(_ body: (_ pointer: UnsafeMutableBufferPointer<Self.Element>) throws -> Result) throws -> Result {
        let protection = try vm_region_basic_info_data_64_t(self.baseAddress!).protection
        let mutableBuffer = UnsafeMutableBufferPointer(mutating: self)
        if protection & (PROT_WRITE | PROT_READ) != (PROT_WRITE | PROT_READ) {
            let result = mprotect(mutableBuffer.baseAddress!, mutableBuffer.count * MemoryLayout<Element>.size, PROT_READ | PROT_WRITE)
            guard result == 0 else { throw MemoryProtectionFailure(bufferDescr: self.debugDescription, code: result) }
        }
        defer {
            // restore original memory protection
            if protection & (PROT_WRITE | PROT_READ) != (PROT_WRITE | PROT_READ) {
                let result = mprotect(mutableBuffer.baseAddress!, mutableBuffer.count * MemoryLayout<Element>.size, protection)
                if result != 0 {
                    Logger.general.error("failed to restore protection \(protection, privacy: .public) for \(self.debugDescription, privacy: .public) with \(result, privacy: .public)")
                }
            }
        }

        return try body(mutableBuffer)
    }

}
