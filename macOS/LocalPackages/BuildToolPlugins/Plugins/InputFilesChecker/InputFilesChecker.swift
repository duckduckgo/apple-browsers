//
//  InputFilesChecker.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import PackagePlugin
import XcodeProjectPlugin

let nonSandboxedExtraInputFiles: Set<InputFile> = Set([
    .init("InfoPlist.xcstrings", .resource),
    .init("DeveloperID.xcstrings", .resource),
    .init("DuckDuckGo VPN.app", .unknown),
    .init("DuckDuckGo Personal Information Removal.app", .unknown),
])

let sandboxedExtraInputFiles: Set<InputFile> = Set([
    .init("AppStore.xcstrings", .resource),
    .init("AppStoreInfoPlist.xcstrings", .resource),
])

/**
 * This dictionary keeps track of input files that are not present in all targets.
 *
 * By default, we expect all input files to be added to all app targets or tests targets.
 * If this is not the case, exceptions should be listed here.
 *
 * Add here files that are not included in all app targets or all unit tests targets.
 * This dictionary is checked at every build and if there are files not listed there, that
 * were otherwise not included in all app/test targets, the build will stop with an error.
 */
let extraInputFiles: [TargetName: Set<InputFile>] = [
    "DuckDuckGo Privacy Browser": nonSandboxedExtraInputFiles,

    "DuckDuckGo Privacy Browser App Store": sandboxedExtraInputFiles,

    "DuckDuckGo Privacy Pro": nonSandboxedExtraInputFiles,

    "Unit Tests": [
        .init("SupportedOSCheckerTests.swift", .source),
    ],

    "Integration Tests": []
]

typealias TargetName = String

// Remove each entry when its source or resource moves into the owning target or a shared package.
// New misplaced inputs still fail the build; stale entries fail so completed stages cannot be forgotten.
let temporarilyAllowedMisplacedFiles: Set<String> = [
    // Stage C: NetworkProtectionPixelEvent.
    "DuckDuckGo/NetworkProtection/AppAndExtensionAndAgentTargets/NetworkProtectionPixelEvent.swift",

    // Stage D: subscription pixels and environment.
    "DuckDuckGo/Application/WideEventFeatureFlagAdapter.swift",
    "DuckDuckGo/Statistics/SubscriptionPixel.swift",
    "DuckDuckGo/Subscription/SubscriptionEnvironment+Default.swift",
    "DuckDuckGo/Subscription/SubscriptionFunnelOrigin.swift",
    "DuckDuckGo/Subscription/SubscriptionPixelHandler.swift",

    // Stage E: VPN and TipKit code shared with the browser.
    "DuckDuckGo/Common/Localizables/UserText+NetworkProtection+Shared.swift",
    "DuckDuckGo/NetworkProtection/AppAndExtensionAndAgentTargets/UserDefaults+NetworkProtectionShared.swift",
    "DuckDuckGo/NetworkProtection/AppAndExtensionAndAgentTargets/VPNIPCResources.swift",
    "DuckDuckGo/NetworkProtection/AppAndExtensionAndAgentTargets/VPNOperationErrorRecorder.swift",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/VPNLocation/DefaultVPNLocationFormatter.swift",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/VPNLocation/NetworkProtectionVPNCountryLabelsModel.swift",
    "DuckDuckGo/Subscription/VPNSettings+Environment.swift",
    "DuckDuckGo/TipKit/Logger+TipKit.swift",
    "DuckDuckGo/TipKit/TipKitAppEventHandling.swift",
    "DuckDuckGo/TipKit/TipKitController+ConvenienceInitializers.swift",
    "DuckDuckGo/TipKit/TipKitController.swift",

    // Stage F: remove UserDefaultsWrapper after KeyedStoring migration.
    "DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift",

    // Shared app icons, VPN assets, configuration, and localizations.
    "DuckDuckGo/AppIcons/AppIcon-Alpha.icon",
    "DuckDuckGo/AppIcons/AppIcon-Debug.icon",
    "DuckDuckGo/AppIcons/AppIcon-Review.icon",
    "DuckDuckGo/AppIcons/AppIcon.icon",
    "DuckDuckGo/ContentBlocker/Resources/macos-config.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/privacypro_devices_legacy.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/sparkleloop_wide_legacy.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/upsell_devices_loop.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/upsell_devices_reveal.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/vpn-animation.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/vpn-dark-mode.json",
    "DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/Assets/vpn-light-mode.json",
    "DuckDuckGo/NetworkProtection/NetworkExtensionTargets/NetworkExtensionAndNotificationTargets/Localizable.xcstrings",
    "DuckDuckGo/NetworkProtection/NetworkExtensionTargets/NetworkExtensionAndNotificationTargets/NetworkProtectionLocalizable.xcstrings",
]

struct InputFile: Hashable, Comparable {
    static func < (lhs: InputFile, rhs: InputFile) -> Bool {
        lhs.fileName < rhs.fileName
    }

    var fileName: String
    var type: FileType

    init(_ fileName: String, _ type: FileType) {
        self.fileName = fileName
        self.type = type
    }

    init(_ file: File) {
        self.fileName = file.path.lastComponent
        self.type = file.type
    }
}

@main
struct TargetSourcesChecker: BuildToolPlugin, XcodeBuildToolPlugin {
    func createBuildCommands(context: PackagePlugin.PluginContext, target: PackagePlugin.Target) async throws -> [PackagePlugin.Command] {
        return []
    }

    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        var appTargets: [XcodeTarget] = []
        var unitTestsTargets: [XcodeTarget] = []
        var integrationTestsTargets: [XcodeTarget] = []
        context.xcodeProject.targets.forEach { target in
            switch target.product?.kind {
            case .application where target.displayName.starts(with: "DuckDuckGo Privacy Browser") && !target.displayName.hasSuffix("launcher"):
                appTargets.append(target)
            case .other("com.apple.product-type.bundle.unit-test"):
                if target.displayName.starts(with: "Unit Tests") {
                    unitTestsTargets.append(target)
                } else if target.displayName.starts(with: "Integration Tests") {
                    integrationTestsTargets.append(target)
                }
            default:
                break
            }
        }

        if appTargets.isEmpty || unitTestsTargets.isEmpty || integrationTestsTargets.isEmpty {
            throw NoTargetsFoundError()
        }

        var errors = [Error]()

        // Validate sources for App Store and DMG builds are present in both targets
        for targets in [appTargets, unitTestsTargets, integrationTestsTargets] {
            do {
                try check(targets)
            } catch {
                errors.append(error)
            }
        }

        // Validate source and resource paths for every Xcode target.
        do {
            try validateTargetSourceFolders(allTargets: context.xcodeProject.targets, projectDirectory: context.xcodeProject.directory)
        } catch {
            errors.append(error)
        }

        try CombinedError(errors: errors).throwIfNonEmpty()

        return []
    }

    /// Keep files compiled or bundled by a target under that target's source directory.
    private func validateTargetSourceFolders(allTargets: [XcodeTarget], projectDirectory: Path) throws {
        var errors = [Error]()
        var misplacedFiles: [String: MisplacedInputFile] = [:]
        var unobservedTemporaryExceptions = temporarilyAllowedMisplacedFiles
        let projectURL = URL(fileURLWithPath: projectDirectory.string).standardizedFileURL
        let projectPathPrefix = projectURL.path + "/"
        let builtProductsPath = projectURL.appendingPathComponent("build").path
        let sharedPrivacyReferenceTests = projectURL.deletingLastPathComponent()
            .appendingPathComponent("SharedPackages/BrowserServicesKit/Tests/BrowserServicesKitTests/Res/privacy-reference-tests").path

        for target in allTargets {
            guard let expectedFolders = expectedSourcesFolders(for: target.displayName) else {
                errors.append(UnknownTargetSourceFolderError(target: target.displayName))
                continue
            }
            let expectedPaths = expectedFolders.map { projectURL.appendingPathComponent($0).path }

            for file in target.inputFiles {
                let filePath = URL(fileURLWithPath: file.path.string).standardizedFileURL.path
                if isIgnoredInputFile(file,
                                      filePath: filePath,
                                      targetName: target.displayName,
                                      builtProductsPath: builtProductsPath,
                                      projectPathPrefix: projectPathPrefix,
                                      sharedPrivacyReferenceTests: sharedPrivacyReferenceTests) { continue }
                guard !expectedPaths.contains(where: { filePath.hasPrefix($0 + "/") }) else { continue }

                if filePath.hasPrefix(projectPathPrefix) {
                    let relativePath = String(filePath.dropFirst(projectPathPrefix.count))
                    if temporarilyAllowedMisplacedFiles.contains(relativePath) {
                        unobservedTemporaryExceptions.remove(relativePath)
                        continue
                    }
                }

                misplacedFiles[filePath, default: MisplacedInputFile()].targets.insert(target.displayName)
                misplacedFiles[filePath, default: MisplacedInputFile()].expectedFolders.formUnion(expectedFolders)
            }
        }

        for relativePath in unobservedTemporaryExceptions.sorted() {
            errors.append(ObsoleteTemporaryInputFileExceptionError(relativePath: relativePath))
        }

        for filePath in misplacedFiles.keys.sorted() {
            guard let issue = misplacedFiles[filePath] else { continue }
            errors.append(FileNotInTargetSourcesFolderError(
                targets: issue.targets,
                filePath: filePath,
                expectedFolders: issue.expectedFolders
            ))
        }

        try CombinedError(errors: errors).throwIfNonEmpty()
    }

    private func isIgnoredInputFile(_ file: File,
                                    filePath: String,
                                    targetName: String,
                                    builtProductsPath: String,
                                    projectPathPrefix: String,
                                    sharedPrivacyReferenceTests: String) -> Bool {
        // Xcode also reports built products as unknown inputs. Keep checking project resources such as icon bundles.
        if file.type == .unknown &&
            (filePath.hasPrefix(builtProductsPath + "/") || !filePath.hasPrefix(projectPathPrefix)) { return true }
        return targetName.starts(with: "Unit Tests") && filePath == sharedPrivacyReferenceTests
    }

    private struct MisplacedInputFile {
        var targets: Set<String> = []
        var expectedFolders: Set<String> = []
    }

    /// Returns directories relative to the macOS project for target-owned inputs.
    private func expectedSourcesFolders(for targetName: String) -> [String]? {
        switch targetName {
        case let name where name.starts(with: "Unit Tests"):
            return ["UnitTests"]
        case let name where name.starts(with: "Integration Tests"):
            return ["IntegrationTests"]
        case "Performance Tests":
            return ["PerformanceTests", "UITests"] // Existing performance tests reuse UI test helpers.
        case "UI Tests":
            return ["UITests"]
        case let name where name.starts(with: "SyncE2EUITests"):
            return ["SyncE2EUITests"]
        case "DBPE2ETests":
            return ["DBPE2ETests"]
        case let name where name.starts(with: "DuckDuckGo Privacy Browser"):
            // DuckDuckGoAppBundle holds the entry point, Info.plist and entitlements; the browser code is the macOS/DuckDuckGo package.
            return ["DuckDuckGo", "DuckDuckGoAppBundle"]
        case "tests-server":
            return ["tests-server"]
        // HelperTargetsShared holds sources compiled into more than one helper target, never into the app.
        case "DuckDuckGoDBPBackgroundAgent", "DuckDuckGoDBPBackgroundAgentAppStore":
            return ["DuckDuckGoDBPBackgroundAgent", "HelperTargetsShared"]
        case "DuckDuckGoVPN", "DuckDuckGoVPNAppStore", "VPNProxyExtension":
            return [targetName == "VPNProxyExtension" ? "VPNProxyExtension" : "DuckDuckGoVPN", "HelperTargetsShared"]
        case "DuckDuckGoVPNSysexAppStore", "NetworkProtectionSystemExtension":
            return ["NetworkProtectionSystemExtension", "HelperTargetsShared"]
        case "NetworkProtectionAppExtension":
            return ["NetworkProtectionAppExtension", "HelperTargetsShared"]
        default:
            return nil
        }
    }

    private func check(_ targets: [XcodeTarget]) throws {
        if targets.isEmpty {
            return
        }

        var commonInputFiles: Set<InputFile> = Set(targets[0].inputFiles.map(InputFile.init))
        for target in targets.dropFirst() {
            commonInputFiles.formIntersection(target.inputFiles.map(InputFile.init))
        }

        var errors = [Error]()

        let filesWithSpaceInPath = targets[0].inputFiles.filter { $0.type != .unknown && $0.path.string.firstIndex(of: " ") != nil }
        if !filesWithSpaceInPath.isEmpty {
            errors.append(contentsOf: filesWithSpaceInPath.map(\.path.string).sorted().map(FileWithSpaceInPathError.init))
        }

        for target in targets {
            let inputFiles = Set(target.inputFiles.map(InputFile.init))
            let extraFiles = inputFiles.subtracting(commonInputFiles)

            let expectedExtraFiles = extraInputFiles[target.displayName] ?? []
            let unrelatedFiles = expectedExtraFiles.subtracting(inputFiles)

            if expectedExtraFiles != extraFiles || !unrelatedFiles.isEmpty {
                let error = ExtraFilesInconsistencyError(
                    target: target.displayName,
                    actual: extraFiles,
                    expected: expectedExtraFiles,
                    unrelated: unrelatedFiles
                )
                print(error.localizedDescription)
                errors.append(error)
            }
        }

        try CombinedError(errors: errors).throwIfNonEmpty()
    }
}

// Explicitely use module name to silence warning for protocol conformance for protocols defined in an external library.
// We run e2e tests on Xcode 15 so we can't use @retroactive keyword.
// More info at https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md
extension File: Swift.Equatable, Swift.Hashable {
    public static func == (lhs: File, rhs: File) -> Bool {
        lhs.path == rhs.path && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(type)
    }
}
