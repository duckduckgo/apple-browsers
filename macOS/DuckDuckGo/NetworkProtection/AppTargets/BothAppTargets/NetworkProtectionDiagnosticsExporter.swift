//
//  NetworkProtectionDiagnosticsExporter.swift
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
import Common
import FoundationExtensions
import Darwin
import Foundation
import LoginItems
import Network
import NetworkProtectionProxy
import OSLog
import Security
import Subscription
import SystemConfiguration
import VPN
import VPNAppState
import os.log

final class NetworkProtectionDiagnosticsExporter {

    // MARK: - Types

    private struct DiagnosticsFile {
        let name: String
        let contents: String
    }

    private struct Command {
        let title: String
        let executablePath: String
        let arguments: [String]
        let timeout: TimeInterval

        init(_ title: String, _ executablePath: String, _ arguments: [String] = [], timeout: TimeInterval = 10) {
            self.title = title
            self.executablePath = executablePath
            self.arguments = arguments
            self.timeout = timeout
        }
    }

    private struct CommandResult {
        let command: Command
        let output: String
        let errorOutput: String
        let terminationStatus: Int32?
        let timedOut: Bool
    }

    private final class ProcessData: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ data: Data) {
            lock.lock()
            self.data = data
            lock.unlock()
        }

        func stringValue() -> String {
            lock.lock()
            let data = self.data
            lock.unlock()

            return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        }
    }

    private struct InterfaceAddress {
        let name: String
        let family: String
        let address: String
        let flags: [String]
    }

    private enum InfoPlistKey {
        static let vpnMenuAgentBundleID = "AGENT_BUNDLE_ID"
        static let sysexBundleID = "SYSEX_BUNDLE_ID"
        static let netPAppGroup = "NETP_APP_GROUP"
        static let ipcAppGroup = "IPC_APP_GROUP"
        static let subscriptionAppGroup = "SUBSCRIPTION_APP_GROUP"
    }

    private enum AppExtensionBundleIDSuffix {
        static let tunnel = ".network-protection-extension"
        static let proxy = ".proxy"
    }

    // MARK: - Dependencies

    private let subscriptionManager: any SubscriptionManager
    private let defaults: UserDefaults
    private let settings: VPNSettings
    private let proxySettings: TransparentProxySettings
    private let vpnAppState: VPNAppState
    private let fileManager: FileManager

    // MARK: - Initializers

    init(subscriptionManager: any SubscriptionManager,
         defaults: UserDefaults = .netP,
         settings: VPNSettings = .init(defaults: .netP),
         proxySettings: TransparentProxySettings = .init(defaults: .netP),
         vpnAppState: VPNAppState = .init(defaults: .netP),
         fileManager: FileManager = .default) {

        self.subscriptionManager = subscriptionManager
        self.defaults = defaults
        self.settings = settings
        self.proxySettings = proxySettings
        self.vpnAppState = vpnAppState
        self.fileManager = fileManager
    }

    // MARK: - Export

    @MainActor
    func exportToDesktop() async throws -> [URL] {
        Logger.networkProtection.info("Exporting VPN diagnostics")

        let files = await collectDiagnosticsFiles()
        let logs = await collectRecentNetworkProtectionLogs()
        let timestamp = Self.fileTimestampFormatter.string(from: Date())
        let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        let overviewURL = desktopURL.appendingPathComponent("duckduckgo-vpn-diagnostics-overview-\(timestamp).txt")
        let logsURL = desktopURL.appendingPathComponent("duckduckgo-vpn-diagnostics-logs-\(timestamp).txt")

        try await writeDiagnosticsFile(files: files, to: overviewURL)
        try await writeDiagnosticsFile(files: [DiagnosticsFile(name: "vpn-recent-logs.txt", contents: logs)], to: logsURL)

        Logger.networkProtection.info("VPN diagnostics exported to \(overviewURL.path, privacy: .public) and \(logsURL.path, privacy: .public)")
        return [overviewURL, logsURL]
    }

    // MARK: - Diagnostics Assembly

    @MainActor
    private func collectDiagnosticsFiles() async -> [DiagnosticsFile] {
        async let feedbackMetadata = collectFeedbackMetadata()
        async let networkState = collectNetworkState()
        async let systemCommandOutput = collectSystemCommandOutput()

        let appState = collectAppState()

        let files = await [
            DiagnosticsFile(name: "README.txt", contents: readme()),
            DiagnosticsFile(name: "vpn-app-state.txt", contents: appState),
            DiagnosticsFile(name: "vpn-feedback-metadata.json", contents: feedbackMetadata),
            DiagnosticsFile(name: "network-state.txt", contents: networkState),
            DiagnosticsFile(name: "system-command-output.txt", contents: systemCommandOutput)
        ]

        return files
    }

    private func writeDiagnosticsFile(files: [DiagnosticsFile], to diagnosticsURL: URL) async throws {
        try await Task.detached {
            let contents = files.map { file in
                """
                ================================================================================
                \(file.name)
                ================================================================================

                \(file.contents)
                """
            }.joined(separator: "\n\n")

            try contents.write(to: diagnosticsURL, atomically: true, encoding: .utf8)
        }.value
    }

    // MARK: - README

    private func readme() -> String {
        """
        DuckDuckGo VPN diagnostics
        Generated at: \(Self.isoDateFormatter.string(from: Date()))

        This file is intended for internal debugging. It includes local system state that can affect the VPN, including DNS, routes,
        interfaces, system extension and login item status, VPN settings, app state, and recent VPN-related logs.
        """
    }

    // MARK: - Feedback Metadata

    @MainActor
    private func collectFeedbackMetadata() async -> String {
        let collector = DefaultVPNMetadataCollector(defaults: defaults, subscriptionManager: subscriptionManager)
        let metadata = await collector.collectMetadata()
        return metadata.toPrettyPrintedJSON() ?? "Failed to encode feedback metadata."
    }

    // MARK: - App State

    private func collectAppState() -> String {
        let vpnMenuAgentBundleID = infoPlistValue(for: InfoPlistKey.vpnMenuAgentBundleID)
        let loginItem = vpnMenuAgentBundleID.map { LoginItem(bundleId: $0, defaults: .netP, logger: Logger.networkProtection) }
        let runningVPNMenuApplications = vpnMenuAgentBundleID.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        } ?? []

        let tunnelAppexBundleID = vpnMenuAgentBundleID.map { $0 + AppExtensionBundleIDSuffix.tunnel }
        let proxyAppexBundleID = vpnMenuAgentBundleID.map { $0 + AppExtensionBundleIDSuffix.proxy }
        let sysexBundleID = infoPlistValue(for: InfoPlistKey.sysexBundleID)

        return """
        \(section("App"))
        App version: \(AppVersion.shared.versionAndBuildNumber)
        OS version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Build flavor: \(AppVersion.isAppStoreBuild ? "appstore" : "dmg")
        Bundle identifier: \(Bundle.main.bundleIdentifier ?? "unknown")
        Is in Applications directory: \(Bundle.main.isInApplicationsDirectory)

        \(section("Bundle identifiers"))
        Main app: \(Bundle.main.bundleIdentifier ?? "unknown")
        VPN menu login item: \(vpnMenuAgentBundleID ?? missingInfoPlistValue(for: InfoPlistKey.vpnMenuAgentBundleID))
        Tunnel app extension: \(tunnelAppexBundleID ?? missingInfoPlistValue(for: InfoPlistKey.vpnMenuAgentBundleID))
        Tunnel system extension: \(sysexBundleID ?? missingInfoPlistValue(for: InfoPlistKey.sysexBundleID))
        Proxy app extension: \(proxyAppexBundleID ?? missingInfoPlistValue(for: InfoPlistKey.vpnMenuAgentBundleID))
        Proxy system extension: \(sysexBundleID ?? missingInfoPlistValue(for: InfoPlistKey.sysexBundleID))

        \(section("App groups"))
        Network Protection: \(infoPlistValue(for: InfoPlistKey.netPAppGroup) ?? missingInfoPlistValue(for: InfoPlistKey.netPAppGroup))
        IPC: \(infoPlistValue(for: InfoPlistKey.ipcAppGroup) ?? missingInfoPlistValue(for: InfoPlistKey.ipcAppGroup))
        Subscriptions: \(infoPlistValue(for: InfoPlistKey.subscriptionAppGroup) ?? missingInfoPlistValue(for: InfoPlistKey.subscriptionAppGroup))

        \(section("Runtime entitlements"))
        com.apple.security.application-groups:
        \(entitlementDescription("com.apple.security.application-groups"))

        com.apple.developer.networking.networkextension:
        \(entitlementDescription("com.apple.developer.networking.networkextension"))

        com.apple.developer.system-extension.install:
        \(entitlementDescription("com.apple.developer.system-extension.install"))

        \(section("Login item"))
        Bundle identifier: \(vpnMenuAgentBundleID ?? missingInfoPlistValue(for: InfoPlistKey.vpnMenuAgentBundleID))
        Status: \(loginItem.map { "\($0.status)" } ?? "unknown")
        Is running: \(loginItem.map { "\($0.isRunning)" } ?? "unknown")
        Running process identifiers:
        \(runningVPNMenuApplications.map(\.processIdentifier).map(String.init).indentedList())

        \(section("VPN app state"))
        Is using system extension: \(vpnAppState.isUsingSystemExtension)
        Don't ask again exclusion suggestion: \(vpnAppState.dontAskAgainExclusionSuggestion)

        \(section("VPN settings"))
        Connect on login: \(settings.connectOnLogin)
        Include all networks: \(settings.includeAllNetworks)
        Enforce routes: \(settings.enforceRoutes)
        Exclude local networks: \(settings.excludeLocalNetworks)
        Notify status changes: \(settings.notifyStatusChanges)
        Show in menu bar: \(settings.showInMenuBar)
        Disable rekeying: \(settings.disableRekeying)
        Selected environment: \(settings.selectedEnvironment.rawValue)
        Selected server: \(settings.selectedServer.stringValue ?? "automatic")
        DNS settings: \(settings.dnsSettings)
        Registration key validity: \(settings.registrationKeyValidity)

        \(section("Transparent proxy exclusions"))
        Excluded apps:
        \(proxySettings.excludedApps.sorted().indentedList())

        App routing rules:
        \(proxySettings.appRoutingRules.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.indentedList())

        Excluded domains:
        \(proxySettings.excludedDomains.sorted().indentedList())
        """
    }

    // MARK: - Network State

    private func collectNetworkState() async -> String {
        async let currentPath = collectCurrentNetworkPath()

        let interfaceAddresses = collectInterfaceAddresses()
        let dnsConfiguration = collectDNSConfiguration()
        let resolvConf = readFile(atPath: "/etc/resolv.conf")

        return await """
        \(section("NWPathMonitor"))
        \(currentPath)

        \(section("Interface addresses"))
        \(interfaceAddresses.map { "\($0.name)\t\($0.family)\t\($0.address)\t\($0.flags.joined(separator: ","))" }.indentedList())

        \(section("SystemConfiguration DNS"))
        \(dnsConfiguration)

        \(section("/etc/resolv.conf"))
        \(resolvConf)
        """
    }

    private func collectCurrentNetworkPath() async -> String {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "NetworkProtectionDiagnosticsExporter.NWPathMonitor.paths"))
        defer {
            monitor.cancel()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        while true {
            if !monitor.currentPath.availableInterfaces.isEmpty {
                let path = monitor.currentPath
                return """
                Status: \(path.status)
                Is expensive: \(path.isExpensive)
                Is constrained: \(path.isConstrained)
                Available interfaces: \(path.availableInterfaces.map(interfaceDescription).joined(separator: ", "))
                Uses Wi-Fi: \(path.usesInterfaceType(.wifi))
                Uses wired Ethernet: \(path.usesInterfaceType(.wiredEthernet))
                Uses cellular: \(path.usesInterfaceType(.cellular))
                Raw description: \(path.anonymousDescription)
                """
            }

            if CFAbsoluteTimeGetCurrent() - startTime >= 3.0 {
                return "Timed out waiting for NWPathMonitor to report interfaces."
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func collectInterfaceAddresses() -> [InterfaceAddress] {
        var interfaceAddresses: [InterfaceAddress] = []
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrsPointer) == 0, let firstAddress = ifaddrsPointer else {
            return []
        }

        defer {
            freeifaddrs(ifaddrsPointer)
        }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = pointer?.pointee {
            defer {
                pointer = interface.ifa_next
            }

            guard let addressPointer = interface.ifa_addr else {
                continue
            }

            let family = Int32(addressPointer.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            let familyDescription = family == AF_INET ? "IPv4" : "IPv6"
            let address = String(cString: host)

            interfaceAddresses.append(.init(
                name: name,
                family: familyDescription,
                address: address,
                flags: flagDescriptions(interface.ifa_flags)
            ))
        }

        return interfaceAddresses
    }

    private func collectDNSConfiguration() -> String {
        guard let store = SCDynamicStoreCreate(nil, "DuckDuckGo VPN Diagnostics" as CFString, nil, nil) else {
            return "Failed to create SCDynamicStore."
        }

        var keys = ["State:/Network/Global/DNS"]
        if let serviceKeys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/DNS" as CFString) as? [String] {
            keys.append(contentsOf: serviceKeys.sorted())
        }

        return keys.map { key in
            let value = SCDynamicStoreCopyValue(store, key as CFString)
            return """
            \(key):
            \(Self.propertyListDescription(value).indent())
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - System Command Output

    private func collectSystemCommandOutput() async -> String {
        let commands = systemCommands()

        return await Task.detached {
            let results = commands.map { Self.runCommand($0) }

            return results.map { result in
                var output = ["### \(result.command.title)"]
                output.append("$ \(([result.command.executablePath] + result.command.arguments).joined(separator: " "))")

                if result.timedOut {
                    output.append("Timed out after \(result.command.timeout) seconds.")
                }

                if let status = result.terminationStatus {
                    output.append("Exit status: \(status)")
                }

                output.append("STDOUT:")
                output.append(result.output.nilIfEmpty ?? "none")

                output.append("STDERR:")
                output.append(result.errorOutput.nilIfEmpty ?? "none")

                return output.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }.value
    }

    // MARK: - Logs

    private func collectRecentNetworkProtectionLogs() async -> String {
        await Task.detached {
            do {
                let store = try OSLogStore.local()
                let startDate = Date().addingTimeInterval(-TimeInterval.minutes(60))
                let position = store.position(date: startDate)
                let predicate = NSPredicate(format: """
                subsystem == %@ \
                OR subsystem == %@ \
                OR subsystem == %@ \
                OR process CONTAINS[c] %@ \
                OR process CONTAINS[c] %@
                """, "Network protection", "com.apple.networkextension", "com.apple.extensionkit", "DuckDuckGo VPN", "NetworkProtection")
                let entries = try store.getEntries(at: position, matching: predicate)
                let logs = entries.compactMap { $0 as? OSLogEntryLog }

                guard !logs.isEmpty else {
                    return "No VPN-related log entries found in the last 60 minutes."
                }

                return logs.map { entry in
                    let timestamp = Self.isoDateFormatter.string(from: entry.date)
                    let level = entry.level.description.map { "\($0)\t" } ?? ""
                    return "\(level)[\(timestamp)]\t[\(entry.process)]\t[\(entry.subsystem)]\t[\(entry.category)]\t\(entry.composedMessage)"
                }.joined(separator: "\n")
            } catch {
                return "Failed to collect recent VPN logs: \(error.localizedDescription)"
            }
        }.value
    }

    // MARK: - System Commands

    private func systemCommands() -> [Command] {
        var commands = [
            Command("System extensions", "/usr/bin/systemextensionsctl", ["list"]),
            Command("DNS resolver configuration", "/usr/sbin/scutil", ["--dns"]),
            Command("Network information", "/usr/sbin/scutil", ["--nwi"]),
            Command("Proxy configuration", "/usr/sbin/scutil", ["--proxy"]),
            Command("Network connection services", "/usr/sbin/scutil", ["--nc", "list"]),
            Command("Hardware ports", "/usr/sbin/networksetup", ["-listallhardwareports"]),
            Command("Network services", "/usr/sbin/networksetup", ["-listallnetworkservices"]),
            Command("IPv4 routing table", "/usr/sbin/netstat", ["-rn", "-f", "inet"]),
            Command("IPv6 routing table", "/usr/sbin/netstat", ["-rn", "-f", "inet6"]),
            Command("Default route", "/sbin/route", ["-n", "get", "default"]),
            Command("Interfaces", "/sbin/ifconfig", ["-a"], timeout: 15)
        ]

        if let vpnMenuAgentBundleID = infoPlistValue(for: InfoPlistKey.vpnMenuAgentBundleID) {
            commands.append(Command("VPN menu login item launchd job", "/bin/launchctl", ["print", "gui/\(getuid())/\(vpnMenuAgentBundleID)"]))
        }

        return commands
    }

    private static func runCommand(_ command: Command) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: command.executablePath) else {
            return .init(command: command,
                         output: "",
                         errorOutput: "Executable not found or not executable at \(command.executablePath).",
                         terminationStatus: nil,
                         timedOut: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .init(command: command,
                         output: "",
                         errorOutput: "Failed to run command: \(error.localizedDescription)",
                         terminationStatus: nil,
                         timedOut: false)
        }

        let group = DispatchGroup()
        let outputData = ProcessData()
        let errorData = ProcessData()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        let deadline = DispatchTime.now() + command.timeout
        let timedOut = group.wait(timeout: deadline) == .timedOut

        if timedOut {
            process.terminate()
            process.waitUntilExit()
            _ = group.wait(timeout: .now() + 1)
        } else {
            process.waitUntilExit()
        }

        return .init(command: command,
                     output: outputData.stringValue(),
                     errorOutput: errorData.stringValue(),
                     terminationStatus: process.terminationStatus,
                     timedOut: timedOut)
    }

    // MARK: - Entitlements

    private func infoPlistValue(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private func missingInfoPlistValue(for key: String) -> String {
        "missing Info.plist value for \(key)"
    }

    private func entitlementDescription(_ entitlement: String) -> String {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else {
            return "unavailable"
        }

        return Self.propertyListDescription(value)
    }

    // MARK: - File Reading

    private func readFile(atPath path: String) -> String {
        guard fileManager.isReadableFile(atPath: path) else {
            return "Not readable."
        }

        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return "Failed to read \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - Network Formatting

    private func interfaceDescription(_ interface: NWInterface) -> String {
        "\(interface.name) (\(interface.type))"
    }

    private func flagDescriptions(_ flags: UInt32) -> [String] {
        [
            (UInt32(IFF_UP), "UP"),
            (UInt32(IFF_RUNNING), "RUNNING"),
            (UInt32(IFF_LOOPBACK), "LOOPBACK"),
            (UInt32(IFF_POINTOPOINT), "POINTOPOINT"),
            (UInt32(IFF_MULTICAST), "MULTICAST"),
            (UInt32(IFF_BROADCAST), "BROADCAST")
        ].compactMap { flag, description in
            flags & flag == flag ? description : nil
        }
    }

    private func section(_ title: String) -> String {
        "### \(title)"
    }

    // MARK: - Text Formatting

    private static func propertyListDescription(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }

        if PropertyListSerialization.propertyList(value, isValidFor: .xml) {
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
                return String(data: data, encoding: .utf8) ?? String(describing: value)
            } catch {
                return "Failed to serialize property list: \(error.localizedDescription)\n\(String(describing: value))"
            }
        }

        return String(describing: value)
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}

private extension Array where Element == String {

    func indentedList() -> String {
        guard !isEmpty else {
            return "  none"
        }

        return map { "  - \($0)" }.joined(separator: "\n")
    }
}

private extension String {

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func indent() -> String {
        components(separatedBy: .newlines)
            .map { "  \($0)" }
            .joined(separator: "\n")
    }
}
