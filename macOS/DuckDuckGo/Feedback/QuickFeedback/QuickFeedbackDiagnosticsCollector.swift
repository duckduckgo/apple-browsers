//
//  QuickFeedbackDiagnosticsCollector.swift
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

import AppKit
import Foundation
import IOKit

final class QuickFeedbackDiagnosticsCollector {

    private weak var tabCountProvider: TabCountProviding?
    private let launchDate: Date

    init(tabCountProvider: TabCountProviding? = nil, launchDate: Date = Date()) {
        self.tabCountProvider = tabCountProvider
        self.launchDate = launchDate
    }

    func collectDiagnostics() -> String {
        var lines = [String]()

        lines.append("--- Diagnostics (auto-collected) ---")

        let appVersionModel = AppVersionModel()
        lines.append("App Version: \(appVersionModel.versionLabelShort) (\(appVersionModel.distributionLabel))")

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

        #if arch(arm64)
        lines.append("Architecture: Apple Silicon (arm64)")
        #elseif arch(x86_64)
        lines.append("Architecture: Intel (x86_64)")
        #else
        lines.append("Architecture: unknown")
        #endif

        lines.append("GPU: \(gpuSummary())")
        lines.append("Memory: \(memorySummary())")
        lines.append("Disk: \(diskSummary())")

        if let provider = tabCountProvider {
            lines.append("Tabs: \(provider.tabCount) tabs / \(provider.windowCount) windows")
        }

        lines.append("Session: \(sessionLength())")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func gpuSummary() -> String {
        var iterator: io_iterator_t = 0
        let port: mach_port_t
        if #available(macOS 12.0, *) {
            port = kIOMainPortDefault
        } else {
            port = kIOMasterPortDefault
        }
        let result = IOServiceGetMatchingServices(port, IOServiceMatching("IOPCIDevice"), &iterator)
        guard result == KERN_SUCCESS else { return "unknown" }
        defer { IOObjectRelease(iterator) }

        var names = [String]()
        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            if let modelData = IORegistryEntryCreateCFProperty(entry, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               let model = String(data: modelData.prefix(while: { $0 != 0 }), encoding: .utf8) {
                names.append(model)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        return names.isEmpty ? "unknown" : names.joined(separator: ", ")
    }

    private func memorySummary() -> String {
        let physicalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let browserMB = info.resident_size / (1024 * 1024)
            return String(format: "%llu MB browser, %.0f GB total", browserMB, physicalGB)
        }
        return String(format: "%.0f GB total", physicalGB)
    }

    private func diskSummary() -> String {
        guard let homeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let freeBytes = values.volumeAvailableCapacityForImportantUsage else {
            return "unknown"
        }
        let freeGB = freeBytes / (1024 * 1024 * 1024)
        return "\(freeGB) GB free"
    }

    private func sessionLength() -> String {
        let uptime = Date().timeIntervalSince(launchDate)
        if uptime < 60 { return "under a minute" }
        if uptime < 3600 { return "\(Int(uptime / 60)) minutes" }
        if uptime < 86400 { return "\(Int(uptime / 3600)) hours" }
        return "\(Int(uptime / 86400)) days"
    }
}

protocol TabCountProviding: AnyObject {
    var tabCount: Int { get }
    var windowCount: Int { get }
}
