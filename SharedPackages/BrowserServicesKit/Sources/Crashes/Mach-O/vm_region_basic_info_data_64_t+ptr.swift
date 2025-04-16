//
//  vm_region_basic_info_data_64_t+ptr.swift
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

struct KernError: Error, RawRepresentable {
    let rawValue: Int32

    init?(rawValue: Int32) {
        guard rawValue != KERN_SUCCESS else { return nil }
        self.rawValue = rawValue
    }
}

extension vm_region_basic_info_data_64_t {

    /// Initializes `vm_region_basic_info_data_64_t` from a pointer, retrieving memory region information.
    /// - Throws: `KernError` if the operation fails.
    init(_ ptr: UnsafeRawPointer) throws {
        var size: vm_size_t = 0
        var address = vm_address_t(bitPattern: ptr)
        var port: mach_port_t = 0
        var count = mach_msg_type_number_t(VM_REGION_BASIC_INFO_64)
        var info = vm_region_basic_info_data_64_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int32.self, capacity: Int(count)) { infoPtr in
                vm_region_64(mach_task_self_, &address, &size, VM_REGION_BASIC_INFO_64, infoPtr, &count, &port)
            }
        }
        if let error = KernError(rawValue: result) { throw error }
        self = info
    }

}
