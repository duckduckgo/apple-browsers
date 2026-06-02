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

import Common
import FoundationExtensions
import Foundation
import IOKit

final class QuickFeedbackDiagnosticsCollector {

    private weak var tabAndWindowCountProvider: TabAndWindowCountProviding?
    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let appVersion: AppVersion
    private let launchDate: Date

    init(tabAndWindowCountProvider: TabAndWindowCountProviding?,
         memoryUsageMonitor: MemoryUsageMonitoring,
         appVersion: AppVersion = AppVersion(),
         launchDate: Date) {
        self.tabAndWindowCountProvider = tabAndWindowCountProvider
        self.memoryUsageMonitor = memoryUsageMonitor
        self.appVersion = appVersion
        self.launchDate = launchDate
    }

    func collectDiagnostics() -> String {
        var lines = [String]()

        lines.append("--- Diagnostics (auto-collected) ---")

        let appVersionModel = AppVersionModel(appVersion: appVersion)
        lines.append("App Version: \(appVersionModel.versionLabelShort) (\(appVersionModel.distributionLabel))")

        lines.append("macOS: \(appVersion.osVersionMajorMinorPatch)")

        lines.append("Architecture: \(compiledArchitecture)")

        lines.append("GPU: \(gpuDevices)")
        lines.append("Memory: \(memorySummary)")
        lines.append("Disk: \(freeDiskSpace)")

        if let provider = tabAndWindowCountProvider {
            lines.append("Tabs: \(provider.tabCount) tabs / \(provider.windowCount) windows")
        }

        lines.append("Session: \(sessionLength)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private var compiledArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    /// Queries IOKit for GPU/display device model names.
    private var gpuDevices: String {
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOPCIDevice")

        let mainPort: mach_port_t = kIOMainPortDefault

        guard IOServiceGetMatchingServices(mainPort, matchingDict, &iterator) == KERN_SUCCESS else {
            return "unknown"
        }
        defer { IOObjectRelease(iterator) }

        var names = [String]()
        var entry: io_registry_entry_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            guard let classCode = IORegistryEntryCreateCFProperty(entry, "class-code" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data,
                  classCode.count >= 3,
                  classCode[2] == 0x03 else { continue }

            if let modelData = IORegistryEntryCreateCFProperty(entry, "model" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data,
               let name = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) {
                names.append(name)
            }
        }

        #if arch(arm64)
        if names.isEmpty {
            var size: size_t = 0
            sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
            if size > 0 {
                var buffer = [CChar](repeating: 0, count: size)
                sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
                let chipName = String(cString: buffer)
                names.append("\(chipName) (integrated)")
            }
        }
        #endif

        return names.isEmpty ? "unknown" : names.joined(separator: ", ")
    }

    private var memorySummary: String {
        let report = memoryUsageMonitor.getCurrentMemoryUsage()
        let physicalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        return "\(report.footprintMemoryString) browser, \(String(format: "%.0f", physicalGB)) GB total"
    }

    private var freeDiskSpace: String {
        guard let homeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let freeBytes = values.volumeAvailableCapacityForImportantUsage else {
            return "unknown"
        }
        let freeGB = Double(freeBytes) / 1_073_741_824.0
        return "\(String(format: "%.1f", freeGB)) GB free"
    }

    private var sessionLength: String {
        let uptime = Date().timeIntervalSince(launchDate)
        if uptime < 60 { return "under a minute" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        return formatter.string(from: uptime) ?? "unknown"
    }
}

protocol TabAndWindowCountProviding: AnyObject {
    var tabCount: Int { get }
    var windowCount: Int { get }
}
