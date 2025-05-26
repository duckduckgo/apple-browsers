//
//  load_command+helpers.swift
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

extension UnsafePointer where Pointee == load_command {

    var cmd: Int32 {
        Int32(bitPattern: pointee.cmd)
    }

    func `as`(_: segment_command_64.Type) -> UnsafePointer<segment_command_64>? {
        guard self.pointee.cmd == LC_SEGMENT_64 else { return nil }
        return UnsafeRawPointer(self).assumingMemoryBound(to: segment_command_64.self)
    }

    func `as`(_: symtab_command.Type) -> UnsafePointer<symtab_command> {
        return UnsafeRawPointer(self).assumingMemoryBound(to: symtab_command.self)
    }

    func `as`(_: dysymtab_command.Type) -> UnsafePointer<dysymtab_command> {
        return UnsafeRawPointer(self).assumingMemoryBound(to: dysymtab_command.self)
    }

}
