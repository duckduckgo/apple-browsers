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
                                  body: TestFiles.pdf(text: "DuckDuckGo test document"))

        static let usdz = Download(path: "/download/test-model.usdz",
                                   filename: "test-model.usdz",
                                   contentType: "model/vnd.usdz+zip",
                                   isAttachment: false,
                                   chunkSize: 64 * 1024,
                                   chunkDelay: 0,
                                   body: TestFiles.usdz())

        static let all: [Download] = [.slowFile, .pdf, .usdz]

        func uniqueFilename() -> String {
            let url = URL(fileURLWithPath: filename)
            let suffix = UUID().uuidString.prefix(8)
            return "\(url.deletingPathExtension().lastPathComponent)-\(suffix).\(url.pathExtension)"
        }
    }
}

private enum TestFiles {

    static func pdf(text: String) -> Data {
        let stream = "BT /F1 24 Tf 72 720 Td (\(text)) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var output = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.utf8.count)
            output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = output.utf8.count
        output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            output += String(format: "%010d 00000 n \n", offset)
        }
        output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        return Data(output.utf8)
    }

    static func usdz() -> Data {
        let scene = Data("""
        #usda 1.0
        (
            defaultPrim = "Cube"
            metersPerUnit = 1
            upAxis = "Y"
        )

        def Cube "Cube"
        {
            double size = 0.2
        }

        """.utf8)
        return storedZip(fileName: "scene.usda", contents: scene, alignment: 64)
    }

    private static func storedZip(fileName: String, contents: Data, alignment: Int) -> Data {
        let name = Data(fileName.utf8)
        let crc = crc32(contents)
        let headerSize = 30 + name.count
        let padding = (alignment - (headerSize + 4) % alignment) % alignment
        var extra = Data()
        extra.appendLittleEndian(UInt16(0x1986))
        extra.appendLittleEndian(UInt16(padding))
        extra.append(Data(count: padding))

        var zip = Data()
        zip.appendLittleEndian(UInt32(0x04034B50))
        zip.appendLittleEndian(UInt16(20))
        zip.appendLittleEndian(UInt16(0))
        zip.appendLittleEndian(UInt16(0))
        zip.appendLittleEndian(UInt16(0))
        zip.appendLittleEndian(UInt16(0x21))
        zip.appendLittleEndian(crc)
        zip.appendLittleEndian(UInt32(contents.count))
        zip.appendLittleEndian(UInt32(contents.count))
        zip.appendLittleEndian(UInt16(name.count))
        zip.appendLittleEndian(UInt16(extra.count))
        zip.append(name)
        zip.append(extra)
        zip.append(contents)

        let centralDirectoryOffset = zip.count
        var central = Data()
        central.appendLittleEndian(UInt32(0x02014B50))
        central.appendLittleEndian(UInt16(20))
        central.appendLittleEndian(UInt16(20))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0x21))
        central.appendLittleEndian(crc)
        central.appendLittleEndian(UInt32(contents.count))
        central.appendLittleEndian(UInt32(contents.count))
        central.appendLittleEndian(UInt16(name.count))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt32(0))
        central.appendLittleEndian(UInt32(0))
        central.append(name)
        zip.append(central)

        zip.appendLittleEndian(UInt32(0x06054B50))
        zip.appendLittleEndian(UInt16(0))
        zip.appendLittleEndian(UInt16(0))
        zip.appendLittleEndian(UInt16(1))
        zip.appendLittleEndian(UInt16(1))
        zip.appendLittleEndian(UInt32(central.count))
        zip.appendLittleEndian(UInt32(centralDirectoryOffset))
        zip.appendLittleEndian(UInt16(0))
        return zip
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
