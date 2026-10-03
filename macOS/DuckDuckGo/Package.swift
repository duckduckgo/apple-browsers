// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Package.swift
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

import PackageDescription
import Foundation

// Xcode maps the app's CI configuration to release for Swift packages. The macOS CI workflows
// set this flag so the browser code sees the same DEBUG condition as before the move.
let forceDebug = ProcessInfo.processInfo.environment["SPM_FORCE_DEBUG"] == "1"

/// The macOS browser code, built in place from `macOS/DuckDuckGo`.
///
/// - `DuckDuckGoBrowser` (static) is linked into the "DuckDuckGo Privacy Browser" app targets,
///   which only add the entry point, Info.plist, entitlements and bundle resources.
/// - `DuckDuckGoBrowserDynamic` is built by `swift build` for running from VSCode/Cursor.
///
/// Bundle resources (strings, JSON, scripts, storyboards, app icons) stay in the app targets and are
/// read from `Bundle.main`. Asset catalogs and Core Data models are processed here, so that their
/// generated symbols and entity classes live in this module.
let package = Package(
    name: "DuckDuckGo",
    defaultLocalization: "en",
    platforms: [
        .macOS("12.3")
    ],
    products: [
        .library(name: "DuckDuckGoBrowser", type: .static, targets: ["DuckDuckGo_Privacy_Browser"]),
        .library(name: "DuckDuckGoBrowserDynamic", type: .dynamic, targets: ["DuckDuckGo_Privacy_Browser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/BareBonesBrowser.git", exact: "0.1.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "4.0.3"),
        .package(url: "https://github.com/pointfreeco/combine-schedulers.git", exact: "1.2.2"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.6.1"),
        .package(path: "../../SharedPackages/AIChat"),
        .package(path: "../../SharedPackages/AttributedMetric"),
        .package(path: "../../SharedPackages/AutomationServer"),
        .package(path: "../../SharedPackages/BrowserServicesKit"),
        .package(path: "../../SharedPackages/Common"),
        .package(path: "../../SharedPackages/DataBrokerProtectionCore"),
        .package(path: "../../SharedPackages/DebugServer"),
        .package(path: "../../SharedPackages/Infrastructure/DesignResourcesKitIcons"),
        .package(path: "../../SharedPackages/EventHub"),
        .package(path: "../../SharedPackages/HangMetrics"),
        .package(path: "../../SharedPackages/Onboarding"),
        .package(path: "../../SharedPackages/Persistence"),
        .package(path: "../../SharedPackages/PixelKit"),
        .package(path: "../../SharedPackages/SERPInstallOrigin"),
        .package(path: "../../SharedPackages/SERPSettings"),
        .package(path: "../../SharedPackages/ScreenTimeDataCleaner"),
        .package(path: "../../SharedPackages/SnapshotTestingSupport"),
        .package(path: "../../SharedPackages/Infrastructure/SystemFrameworksExtensions"),
        .package(path: "../../SharedPackages/UIComponents"),
        .package(path: "../../SharedPackages/URLPredictor"),
        .package(path: "../../SharedPackages/VPN"),
        .package(path: "../../SharedPackages/WebExtensions"),
        .package(path: "../../SharedPackages/WideEvent"),
        .package(path: "../LocalPackages/AddressBarPerformance"),
        .package(path: "../LocalPackages/AppInfoRetriever"),
        .package(path: "../LocalPackages/AppKitExtensions"),
        .package(path: "../LocalPackages/AppUpdater"),
        .package(path: "../LocalPackages/BWIntegration"),
        .package(path: "../LocalPackages/CommonObjCExtensions"),
        .package(path: "../LocalPackages/CrashReporting"),
        .package(path: "../LocalPackages/DataBrokerProtection-macOS"),
        .package(path: "../LocalPackages/FeatureFlags-macOS"),
        .package(path: "../LocalPackages/Freemium"),
        .package(path: "../LocalPackages/HistoryView"),
        .package(path: "../LocalPackages/LetsMove"),
        .package(path: "../LocalPackages/LoginItems"),
        .package(path: "../LocalPackages/NetworkProtectionMac"),
        .package(path: "../LocalPackages/NetworkQualityMonitor"),
        .package(path: "../LocalPackages/NewTabPage"),
        .package(path: "../LocalPackages/PerformanceTest"),
        .package(path: "../LocalPackages/PreferencesUI-macOS"),
        .package(path: "../LocalPackages/SubscriptionUI"),
        .package(path: "../LocalPackages/SwiftUIExtensions"),
        .package(path: "../LocalPackages/SyncUI-macOS"),
        .package(path: "../LocalPackages/SystemExtensionManager"),
        .package(path: "../LocalPackages/Utilities"),
        .package(path: "../LocalPackages/WebKitExtensions"),
    ],
    targets: [
        .target(
            // Keeps the module name of the former app target: storyboards, archived class names
            // and `@testable import` in the app tests refer to it.
            name: "DuckDuckGo_Privacy_Browser",
            dependencies: [
                // Used through String extensions (`idnaDecoded`), which don't need an import in Swift 5.
                .product(name: "Punycode", package: "PunycodeSwift"),
                .product(name: "AddressBarPerformance", package: "AddressBarPerformance"),
                .product(name: "AIChat", package: "AIChat"),
                .product(name: "AIChatDebugServer", package: "AIChat"),
                .product(name: "AppInfoRetriever", package: "AppInfoRetriever"),
                .product(name: "AppKitExtensions", package: "AppKitExtensions"),
                .product(name: "AppUpdaterShared", package: "AppUpdater"),
                .product(name: "SparkleAppUpdater", package: "AppUpdater"),
                .product(name: "AttributedMetric", package: "AttributedMetric"),
                .product(name: "AutomationServer", package: "AutomationServer"),
                .product(name: "BareBonesBrowserKit", package: "BareBonesBrowser"),
                .product(name: "AutoconsentStats", package: "BrowserServicesKit"),
                .product(name: "Bookmarks", package: "BrowserServicesKit"),
                .product(name: "BrokenSitePrompt", package: "BrowserServicesKit"),
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Configuration", package: "BrowserServicesKit"),
                .product(name: "ContentBlocking", package: "BrowserServicesKit"),
                .product(name: "Crashes", package: "BrowserServicesKit"),
                .product(name: "DDGNavigation", package: "BrowserServicesKit"),
                .product(name: "DDGSync", package: "BrowserServicesKit"),
                .product(name: "DuckPlayer", package: "BrowserServicesKit"),
                .product(name: "History", package: "BrowserServicesKit"),
                .product(name: "MaliciousSiteProtection", package: "BrowserServicesKit"),
                .product(name: "PageRefreshMonitor", package: "BrowserServicesKit"),
                .product(name: "PixelExperimentKit", package: "BrowserServicesKit"),
                .product(name: "PrivacyConfig", package: "BrowserServicesKit"),
                .product(name: "PrivacyConfigTestsUtils", package: "BrowserServicesKit"),
                .product(name: "PrivacyDashboard", package: "BrowserServicesKit"),
                .product(name: "PrivacyStats", package: "BrowserServicesKit"),
                .product(name: "RemoteMessaging", package: "BrowserServicesKit"),
                .product(name: "SpecialErrorPages", package: "BrowserServicesKit"),
                .product(name: "Subscription", package: "BrowserServicesKit"),
                .product(name: "Suggestions", package: "BrowserServicesKit"),
                .product(name: "SyncDataProviders", package: "BrowserServicesKit"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "BWIntegration", package: "BWIntegration"),
                .product(name: "BWManagement", package: "BWIntegration"),
                .product(name: "BWManagementShared", package: "BWIntegration"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                .product(name: "Common", package: "Common"),
                .product(name: "CommonObjCExtensions", package: "CommonObjCExtensions"),
                .product(name: "CrashReporting", package: "CrashReporting"),
                .product(name: "CrashReportingShared", package: "CrashReporting"),
                .product(name: "DataBrokerProtection-macOS", package: "DataBrokerProtection-macOS"),
                .product(name: "DataBrokerProtectionCore", package: "DataBrokerProtectionCore"),
                .product(name: "DebugServer", package: "DebugServer"),
                .product(name: "DesignResourcesKitIcons", package: "DesignResourcesKitIcons"),
                .product(name: "EventHub", package: "EventHub"),
                .product(name: "FeatureFlags-macOS", package: "FeatureFlags-macOS"),
                .product(name: "Freemium", package: "Freemium"),
                .product(name: "HangMetrics", package: "HangMetrics"),
                .product(name: "HistoryView", package: "HistoryView"),
                .product(name: "LetsMove", package: "LetsMove"),
                .product(name: "LoginItems", package: "LoginItems"),
                .product(name: "Lottie", package: "lottie-spm"),
                .product(name: "NetworkProtectionIPC", package: "NetworkProtectionMac"),
                .product(name: "NetworkProtectionProxy", package: "NetworkProtectionMac"),
                .product(name: "NetworkProtectionUI", package: "NetworkProtectionMac"),
                .product(name: "VPNAppLauncher", package: "NetworkProtectionMac"),
                .product(name: "VPNAppState", package: "NetworkProtectionMac"),
                .product(name: "NetworkQualityMonitor", package: "NetworkQualityMonitor"),
                .product(name: "NewTabPage", package: "NewTabPage"),
                .product(name: "Onboarding", package: "Onboarding"),
                .product(name: "PerformanceTest", package: "PerformanceTest"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "PreferencesUI-macOS", package: "PreferencesUI-macOS"),
                .product(name: "ScreenTimeDataCleaner", package: "ScreenTimeDataCleaner"),
                .product(name: "SERPInstallOrigin", package: "SERPInstallOrigin"),
                .product(name: "SERPSettings", package: "SERPSettings"),
                .product(name: "PreviewSnapshots", package: "SnapshotTestingSupport"),
                .product(name: "SubscriptionUI", package: "SubscriptionUI"),
                .product(name: "SwiftUIExtensions", package: "SwiftUIExtensions"),
                .product(name: "SyncUI-macOS", package: "SyncUI-macOS"),
                .product(name: "SystemExtensionManager", package: "SystemExtensionManager"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "UIComponents", package: "UIComponents"),
                .product(name: "URLPredictor", package: "URLPredictor"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "VPN", package: "VPN"),
                .product(name: "WebExtensions", package: "WebExtensions"),
                .product(name: "WebKitExtensions", package: "WebKitExtensions"),
                .product(name: "WideEvent", package: "WideEvent"),
            ],
            path: ".",
            exclude: [
                // Shared with the helper targets; the Xcode targets bundle them.
                "AppIcons",
                "ContentBlocker/Resources/macos-config.json",
                "NetworkProtection/NetworkExtensionTargets",
                // Not built.
                "Package.resolved",
                "Package.swift",
                "Autoconsent/userscript.js",
                "DataImport/Bookmarks/HTML/README.md",
                "Documentation.docc",
                "NavigationBar/View/Animations/shield.new.json",
                "Preferences/Model/LegacySyncPreferences.swift",
                "privacypro_devices.json",
                "VisualRefresh/File.txt",
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("BookmarksBar/View/Prompt/BookmarksBarPromptAssets.xcassets"),
                .process("Autoconsent/autoconsent-bundle.js"),
                .process("ContentBlocker/Resources/trackerData.json"),
                .process("Feedback/New/Animations"),
                .process("Fire/Resources"),
                .process("Localizable.xcstrings"),
                .process("MaliciousSiteProtection/Resources"),
                .process("NavigationBar/View/Animations/Resources"),
                .process("NetworkProtection/AppTargets/BothAppTargets/Assets"),
                .process("Onboarding/ContextualOnboarding/ViewHighlighter/view_highlight.json"),
                .process("Permissions/Inspector/permissions-inspector.html"),
                .process("Permissions/Inspector/permissions-inspector.js"),
                .process("SmarterEncryption/Resources"),
                .process("Bookmarks/Legacy/Bookmark.xcdatamodeld"),
                .process("Favicons/Services/Favicons.xcdatamodeld"),
                .process("FileDownload/Services/Downloads.xcdatamodeld"),
                .process("Fireproofing/Model/FireproofDomains.xcdatamodeld"),
                .process("History/Services/History.xcdatamodeld"),
                .process("Permissions/Model/Permissions.xcdatamodeld"),
                .process("Statistics/ATB/PixelDataModel.xcdatamodeld"),
                .process("UnprotectedDomains/UnprotectedDomains.xcdatamodeld"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ] + (forceDebug ? [.define("DEBUG")] : [])
        ),
    ],
    swiftLanguageVersions: [.v5]
)
