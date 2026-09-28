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

import BrowserServicesKit
import Common
import Foundation
import FoundationExtensions
import IOKit

final class QuickFeedbackDiagnosticsCollector {

    private weak var tabAndWindowCountProvider: TabAndWindowCountProviding?
    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let launchDate: Date

    init(tabAndWindowCountProvider: TabAndWindowCountProviding?,
         memoryUsageMonitor: MemoryUsageMonitoring,
         launchDate: Date) {
        self.tabAndWindowCountProvider = tabAndWindowCountProvider
        self.memoryUsageMonitor = memoryUsageMonitor
        self.launchDate = launchDate
    }

    /// Supplementary device details for an internal feedback report, keyed for the message bridge.
    /// OS version and architecture are provided separately as top-level fields on `InternalFeedbackDeviceInfo`.
    func collectDiagnostics() -> [String: String] {
        var fields = [
            "GPU": gpuDevices,
            "Memory": memorySummary,
            "Disk": freeDiskSpace,
            "Session": sessionLength,
        ]

        if let provider = tabAndWindowCountProvider {
            fields["Tabs"] = String(provider.tabCount)
            fields["Windows"] = String(provider.windowCount)
        }

        return fields
    }

    // MARK: - Private

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
        let webContentProcessCount = report.webContentProcessCount.map { " (\($0) processes)" } ?? ""
        return [
            "\(report.footprintMemoryString) browser",
            "\(report.webContentMemoryString) web content\(webContentProcessCount)",
            "\(String(format: "%.0f", physicalGB)) GB total",
        ].joined(separator: ", ")
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

/// Supplies macOS device details for the Internal Feedback web app, provided over the message bridge.
/// `diagnostics` carries the supplementary values (GPU, memory, disk, tab counts, session length)
/// that aren't already top level fields.
///
final class InternalFeedbackDeviceInfoProvider: InternalFeedbackDeviceInfoProviding {

    private let diagnosticsCollector: QuickFeedbackDiagnosticsCollector
    private let appVersion: AppVersion

    private static var machineArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    init(diagnosticsCollector: QuickFeedbackDiagnosticsCollector, appVersion: AppVersion = AppVersion()) {
        self.diagnosticsCollector = diagnosticsCollector
        self.appVersion = appVersion
    }

    private static var hardwareModel: String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    @MainActor
    func deviceInfo() -> InternalFeedbackDeviceInfo {
        InternalFeedbackDeviceInfo(
            platform: "macos",
            appVersion: appVersion.versionNumber,
            osName: "macOS",
            osVersion: appVersion.osVersionMajorMinorPatch,
            appBuild: appVersion.buildNumber,
            formFactor: "desktop",
            architecture: Self.machineArchitecture,
            locale: Locale.current.localeIdentifierAsJsonFormat,
            channel: AppVersionModel(appVersion: appVersion).distributionLabel,
            deviceModel: Self.hardwareModel,
            deviceManufacturer: "Apple",
            diagnostics: diagnosticsCollector.collectDiagnostics()
        )
    }
}
