//
//  LocalUITestWebsite+Downloads.swift
//  DuckDuckGo
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

import Foundation

extension LocalUITestWebsite {

    struct Download {
        let path: String
        let filename: String
        let contentType: String
        let isAttachment: Bool
        let chunkSize: Int
        let chunkDelay: TimeInterval
        let body: Data

        static let slowFile = Download(path: "/download/slow-file.bin",
                                       filename: "slow-file.bin",
                                       contentType: "application/octet-stream",
                                       isAttachment: true,
                                       chunkSize: 16 * 1024,
                                       chunkDelay: 0.25,
                                       body: Data(repeating: 0x2A, count: 2 * 1024 * 1024))

        static let pdf = Download(path: "/download/test-document.pdf",
                                  filename: "test-document.pdf",
                                  contentType: "application/pdf",
                                  isAttachment: true,
                                  chunkSize: 64 * 1024,
                                  chunkDelay: 0,
                                  body: TestResources.data(named: "test-document.pdf"))

        static let usdz = Download(path: "/download/test-model.usdz",
                                   filename: "test-model.usdz",
                                   contentType: "model/vnd.usdz+zip",
                                   isAttachment: false,
                                   chunkSize: 64 * 1024,
                                   chunkDelay: 0,
                                   body: TestResources.data(named: "test-model.usdz"))

        static let all: [Download] = [.slowFile, .pdf, .usdz]

        func uniqueFilename() -> String {
            let url = URL(fileURLWithPath: filename)
            let suffix = UUID().uuidString.prefix(8)
            return "\(url.deletingPathExtension().lastPathComponent)-\(suffix).\(url.pathExtension)"
        }
    }
}

private final class TestResources {
    static func data(named name: String) -> Data {
        guard let url = Bundle(for: TestResources.self).url(forResource: name, withExtension: nil),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing UI test resource \(name)")
        }
        return data
    }
}
