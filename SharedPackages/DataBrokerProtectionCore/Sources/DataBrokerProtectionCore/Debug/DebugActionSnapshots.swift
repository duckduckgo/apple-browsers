//
//  DebugActionSnapshots.swift
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

#if DEBUG
import Foundation
import ImageIO
import WebKit

@MainActor
final class DebugActionSnapshots {
    enum Moment: String {
        case before, result, error
    }

    nonisolated static let isEnabled = ProcessInfo.processInfo.environment["PIR_DEBUG_SNAPSHOTS"] == "1"

    static let current: DebugActionSnapshots? = {
        let environment = ProcessInfo.processInfo.environment
        guard isEnabled,
              let instance = environment["PIR_DEBUG_INSTANCE_ID"], UUID(uuidString: instance) != nil else { return nil }
#if os(macOS)
        if let path = environment["PIR_DEBUG_SNAPSHOT_DIRECTORY"], path.hasPrefix("/") {
            return DebugActionSnapshots(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
#endif
        return DebugActionSnapshots(directory: FileManager.default.temporaryDirectory.appendingPathComponent("pir-snapshots-\(instance)"))
    }()

    private let directory: URL
    private var sequence = 0

    init(directory: URL) {
        self.directory = directory
    }

    func capture(webView: WKWebView?, step: StepType, action: ActionType, moment: Moment) async -> String? {
        sequence += 1
        let stem = "\(String(format: "%08d", sequence))-\(step.rawValue)-\(action.rawValue)-\(moment.rawValue)"
        let data: Data?
        if let webView, let image = await webView.pirViewportSnapshot(in: webView.bounds) {
            data = pngData(image)
        } else {
            data = nil
        }
        let name = stem + (data == nil ? ".unavailable" : ".png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try (data ?? Data()).write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    private func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
#endif
