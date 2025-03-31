//
//  mach_header+helpers.swift
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

import Foundation
import MachO

#if !(arch(x86_64) || arch(arm64))
    #error("This code is only compatible with 64-bit architecture. Adjust the Mach Header definitions (like segment_command_64, LC_SEGMENT_64 and others) for current platform")
#endif

/// Helper to iterate through Mach-O loader commands.
extension UnsafePointer where Pointee == mach_header_64 {

    struct LoadCommands: Sequence {
        let header: UnsafePointer<mach_header_64>

        struct LoadCommandIterator: IteratorProtocol {
            var current: UnsafeRawPointer
            var count: UInt32

            init(header: UnsafePointer<mach_header_64>) {
                self.current = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
                self.count = header.pointee.ncmds
            }

            mutating func next() -> UnsafePointer<load_command>? {
                guard count > 0 else { return nil }

                let loadCommand = current.bindMemory(to: load_command.self, capacity: 1)
                current = current.advanced(by: Int(loadCommand.pointee.cmdsize))
                count -= 1

                return loadCommand
            }
        }

        func makeIterator() -> LoadCommandIterator {
            LoadCommandIterator(header: header)
        }
    }

    var loadCommands: LoadCommands {
        return LoadCommands(header: self)
    }

}
