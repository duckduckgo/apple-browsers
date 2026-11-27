//
//  BundledLlamaRuntimeTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import Foundation
import LlamaRuntime
import Testing

@Suite("Bundled llama.cpp runtime")
struct BundledLlamaRuntimeTests {

    private static let gigabyte: UInt64 = 1_073_741_824

    private func makeLibraryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("llama-\(UUID().uuidString)")
        try Data().write(to: url)
        return url
    }

    @available(iOS 16, macOS 13, *)
    @Test("A device with less RAM than the minimum isn't supported", .timeLimit(.minutes(1)))
    func tooLittleRAMIsUnsupported() throws {
        let libraryURL = try makeLibraryFile()
        defer { try? FileManager.default.removeItem(at: libraryURL) }

        let runtime = BundledLlamaRuntime(libraryURL: libraryURL, minimumPhysicalMemory: 5 * Self.gigabyte, physicalMemory: 4 * Self.gigabyte)

        #expect(!runtime.isSupported)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enough RAM and a bundled library are supported wherever llama.cpp runs", .timeLimit(.minutes(1)))
    func enoughRAMIsSupported() throws {
        let libraryURL = try makeLibraryFile()
        defer { try? FileManager.default.removeItem(at: libraryURL) }

        let runtime = BundledLlamaRuntime(libraryURL: libraryURL, minimumPhysicalMemory: 5 * Self.gigabyte, physicalMemory: 6 * Self.gigabyte)

        #expect(runtime.isSupported == LlamaLibrary.isSupportedSystem)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No bundled library isn't supported", .timeLimit(.minutes(1)))
    func missingLibraryIsUnsupported() {
        let runtime = BundledLlamaRuntime(libraryURL: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)"))

        #expect(!runtime.isSupported)
    }
}
