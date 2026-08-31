// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        // Exported libraries
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "DDGSync", targets: ["DDGSync"]),
        .library(name: "BrowserServicesKitTestsUtils", targets: ["BrowserServicesKitTestsUtils"]),
        .library(name: "DuckAiDataStore", targets: ["DuckAiDataStore"]),
        .library(name: "SecureStorageTestsUtils", targets: ["SecureStorageTestsUtils"]),
        .library(name: "Bookmarks", targets: ["Bookmarks"]),
        .library(name: "BloomFilterWrapper", targets: ["BloomFilterWrapper"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Crashes", targets: ["Crashes"]),
        .library(name: "CxxCrashHandler", targets: ["CxxCrashHandler"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"]),
        .library(name: "PrivacyConfig", targets: ["PrivacyConfig"]),
        .library(name: "PrivacyConfigTestsUtils", targets: ["PrivacyConfigTestsUtils"]),
        .library(name: "PrivacyDashboard", targets: ["PrivacyDashboard"]),
        .library(name: "Configuration", targets: ["Configuration"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "NetworkingTestingUtils", targets: ["NetworkingTestingUtils"]),
        .library(name: "RemoteMessaging", targets: ["RemoteMessaging"]),
        .library(name: "RemoteMessagingTestsUtils", targets: ["RemoteMessagingTestsUtils"]),
        .library(name: "Navigation", targets: ["Navigation"]),
        .library(name: "SyncDataProviders", targets: ["SyncDataProviders"]),
        .library(name: "SecureStorage", targets: ["SecureStorage"]),
        .library(name: "Subscription", targets: ["Subscription"]),
        .library(name: "SubscriptionTestingUtilities", targets: ["SubscriptionTestingUtilities"]),
        .library(name: "History", targets: ["History"]),
        .library(name: "Suggestions", targets: ["Suggestions"]),
        .library(name: "SpecialErrorPages", targets: ["SpecialErrorPages"]),
        .library(name: "DuckPlayer", targets: ["DuckPlayer"]),
        .library(name: "MaliciousSiteProtection", targets: ["MaliciousSiteProtection"]),
        .library(name: "PixelExperimentKit", targets: ["PixelExperimentKit"]),
        .library(name: "BrokenSitePrompt", targets: ["BrokenSitePrompt"]),
        .library(name: "PageRefreshMonitor", targets: ["PageRefreshMonitor"]),
        .library(name: "PrivacyStats", targets: ["PrivacyStats"]),
        .library(name: "AutoconsentStats", targets: ["AutoconsentStats"]),
        .library(name: "SharedObjCTestsUtils", targets: ["SharedObjCTestsUtils"]),
        .library(name: "WKAbstractions", targets: ["WKAbstractions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/duckduckgo-autofill.git", exact: "19.2.0"),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit.git", exact: "4.0.0"),
        .package(url: "https://github.com/duckduckgo/sync_crypto", exact: "0.7.0"),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", exact: "9.10.2"),
        .package(url: "https://github.com/httpswift/swifter.git", exact: "1.5.0"),
        .package(url: "https://github.com/1024jp/GzipSwift.git", exact: "6.0.1"),
        .package(url: "https://github.com/vapor/jwt-kit.git", exact: "4.13.5"),
        .package(url: "https://github.com/pointfreeco/swift-clocks.git", exact: "1.1.0"),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts.git", revision: "c4c7ef3"),
        .package(path: "../DDGError"),
        .package(path: "../Common"),
        .package(path: "../Persistence"),
        .package(path: "../PixelKit"),
        .package(path: "../Infrastructure/SystemFrameworksExtensions"),
    ],
    targets: [
        .binaryTarget(
            name: "BloomFilter",
            url: "https://github.com/duckduckgo/bloom_cpp/releases/download/3.0.4/BloomFilter.xcframework.zip",
            checksum: "137fefd4a0ccf79560d7071d3387475806b84a7719785a6f80ea9c1d838c7d6b"
        ),
        .binaryTarget(
            name: "GRDB",
            url: "https://github.com/duckduckgo/GRDB.swift/releases/download/2.4.2/GRDB.xcframework.zip",
            checksum: "5380265b0e70f0ed28eb1e12640eb6cde5e4bfd39893c86b31f8d17126887174"
        ),
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                .product(name: "Autofill", package: "duckduckgo-autofill"),
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                .product(name: "Persistence", package: "Persistence"),
                "PrivacyConfig",
                "TrackerRadarKit",
                "BloomFilterWrapper",
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "UserScript",
                "ContentBlocking",
                "SecureStorage",
                "Subscription",
                .product(name: "PixelKit", package: "PixelKit"),
                "Navigation"
            ],
            resources: [
                .process("SmarterEncryption/Store/HTTPSUpgrade.xcdatamodeld"),
                .copy("../../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "BrowserServicesKitTestsUtils",
            dependencies: [
                "BrowserServicesKit",
                "Navigation",
                "WKAbstractions",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "DuckAiDataStore",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Persistence", package: "Persistence"),
                "SecureStorage",
                "GRDB",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PrivacyConfig",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "ContentBlocking",
                .product(name: "Persistence", package: "Persistence"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PrivacyConfigTestsUtils",
            dependencies: [
                "PrivacyConfig",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Bookmarks",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            resources: [
                .process("BookmarksModel.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "History",
            dependencies: [
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            resources: [
                .process("CoreData/BrowsingHistory.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Suggestions",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "BookmarksTestDBBuilder",
            dependencies: [
                "Bookmarks",
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/BookmarksTestDBBuilder"
        ),
        .executableTarget(
            name: "HistoryTestDBBuilder",
            dependencies: [
                "History",
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/HistoryTestDBBuilder"
        ),
        .target(
            name: "BookmarksTestsUtils",
            dependencies: [
                "Bookmarks",
            ]
        ),
        .target(
            name: "BloomFilterObjC",
            dependencies: [
                "BloomFilter"
            ]),
        .target(
            name: "BloomFilterWrapper",
            dependencies: [
                "BloomFilterObjC",
            ]),
        .target(
            name: "Crashes",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "CxxCrashHandler",
                .product(name: "Persistence", package: "Persistence")
            ]),
        .target(
            name: "CxxCrashHandler",
            dependencies: ["Common"]
        ),
        .target(
            name: "DDGSync",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
                .product(name: "Gzip", package: "GzipSwift"),
                "Networking",
                "PrivacyConfig",
            ],
            resources: [
                .process("SyncMetadata.xcdatamodeld"),
                .process("SyncPDFTemplate.png")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "SyncMetadataTestDBBuilder",
            dependencies: [
                "DDGSync",
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/SyncMetadataTestDBBuilder"
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Navigation",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("WILLPERFORMCLIENTREDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_IS_REDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_MAIN_FRAME_NAVIGATION_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_PERFORMANCE_ENABLED", .when(platforms: [.macOS])),
                .define("TERMINATE_WITH_REASON_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED", .when(platforms: [.macOS])),
                .define("_SESSION_STATE_WITH_FILTER_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_AUTOPLAY_POLICY_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "UserScript",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PrivacyDashboard",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "TrackerRadarKit",
                "UserScript",
                "ContentBlocking",
                .product(name: "Persistence", package: "Persistence"),
                "PrivacyConfig",
                "MaliciousSiteProtection",
                .product(name: "PrivacyDashboardResources", package: "privacy-dashboard"),
                "Navigation",
            ],
            path: "Sources/PrivacyDashboard",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Configuration",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "Networking",
                "PrivacyConfig",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Networking",
            dependencies: [
                .product(name: "DDGError", package: "DDGError"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "NetworkingTestingUtils",
            dependencies: [
                "Networking",
            ]
        ),
        .target(
            name: "RemoteMessaging",
            dependencies: [
                "BrowserServicesKit",
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "Configuration",
                "Networking",
                .product(name: "Persistence", package: "Persistence"),
                "PrivacyConfig",
            ],
            resources: [
                .process("CoreData/RemoteMessaging.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "RemoteMessagingTestsUtils",
            dependencies: [
                "RemoteMessaging",
            ]
        ),
        .target(
            name: "SyncDataProviders",
            dependencies: [
                "Bookmarks",
                "BrowserServicesKit",
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "DDGSync",
                "GRDB",
                .product(name: "Persistence", package: "Persistence"),
                "SecureStorage",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SecureStorage",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "PixelKit", package: "PixelKit"),
                "GRDB",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SecureStorageTestsUtils",
            dependencies: [
                "SecureStorage",
                .product(name: "PixelKit", package: "PixelKit")
            ]
        ),
        .target(
            name: "Subscription",
            dependencies: [
                .product(name: "DDGError", package: "DDGError"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "Networking",
                "UserScript",
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "Persistence", package: "Persistence"),
                "SecureStorage"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SubscriptionTestingUtilities",
            dependencies: [
                "BrowserServicesKitTestsUtils",
                "Subscription",
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "NetworkingTestingUtils",
            ]
        ),
        .target(
            name: "SpecialErrorPages",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "UserScript",
                "BrowserServicesKit",
                "MaliciousSiteProtection",
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "DuckPlayer",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "ContentBlocking",
                "PrivacyConfig",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "MaliciousSiteProtection",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                "Networking",
                .product(name: "PixelKit", package: "PixelKit"),
                "PrivacyConfig",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PixelExperimentKit",
            dependencies: [
                .product(name: "PixelKit", package: "PixelKit"),
                "PrivacyConfig",
                "Configuration"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "BrokenSitePrompt",
            dependencies: [
                "PrivacyConfig"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PageRefreshMonitor",
            dependencies: [
                "BrowserServicesKit"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PrivacyStats",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Persistence", package: "Persistence"),
                "TrackerRadarKit"
            ],
            resources: [
                .process("PrivacyStats.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "AutoconsentStats",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "WKAbstractions",
            dependencies: [],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        // MARK: - Test Targets
        .target(
            name: "SharedObjCTestsUtils",
            dependencies: [],
            sources: [
                "SharedObjCTestsUtils.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .testTarget(
            name: "HistoryTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "History",
                "BookmarksTestsUtils",
            ],
            resources: [
                .copy("Resources/BrowsingHistory_V1.sqlite"),
                .copy("Resources/BrowsingHistory_V1.sqlite-shm"),
                .copy("Resources/BrowsingHistory_V1.sqlite-wal"),
            ]
        ),
        .testTarget(
            name: "SuggestionsTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "Suggestions",
            ]
        ),
        .testTarget(
            name: "BookmarksTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "Bookmarks",
                "BookmarksTestsUtils",
            ],
            resources: [
                .copy("Resources/Bookmarks_V1.sqlite"),
                .copy("Resources/Bookmarks_V1.sqlite-shm"),
                .copy("Resources/Bookmarks_V1.sqlite-wal"),
                .copy("Resources/Bookmarks_V2.sqlite"),
                .copy("Resources/Bookmarks_V2.sqlite-shm"),
                .copy("Resources/Bookmarks_V2.sqlite-wal"),
                .copy("Resources/Bookmarks_V3.sqlite"),
                .copy("Resources/Bookmarks_V3.sqlite-shm"),
                .copy("Resources/Bookmarks_V3.sqlite-wal"),
                .copy("Resources/Bookmarks_V4.sqlite"),
                .copy("Resources/Bookmarks_V4.sqlite-shm"),
                .copy("Resources/Bookmarks_V4.sqlite-wal"),
                .copy("Resources/Bookmarks_V5.sqlite"),
                .copy("Resources/Bookmarks_V5.sqlite-shm"),
                .copy("Resources/Bookmarks_V5.sqlite-wal"),
            ]
        ),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "BrowserServicesKit",
                "BrowserServicesKitTestsUtils",
                "SecureStorageTestsUtils",
                "Subscription",
                .product(name: "Persistence", package: "Persistence"),
                "PrivacyConfigTestsUtils",
                "WKAbstractions",
            ],
            resources: [
                // Xcode CodeSign build step fails for iOS target with "bundle format unrecognized, invalid, or unsuitable"
                // when the folder is named "Resources"
                //
                // https://stackoverflow.com/questions/29271548/code-sign-error-bundle-format-unrecognized-invalid-or-unsuitable
                .copy("Res")
            ]
        ),
        .testTarget(
            name: "CrashesTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "Crashes",
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(
            name: "DDGSyncTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "BookmarksTestsUtils",
                "DDGSync",
                .product(name: "Persistence", package: "Persistence"),
                "PrivacyConfigTestsUtils",
                "NetworkingTestingUtils"
            ],
            resources: [
                .copy("Resources/SyncMetadata_V3.sqlite"),
                .copy("Resources/SyncMetadata_V3.sqlite-shm"),
                .copy("Resources/SyncMetadata_V3.sqlite-wal"),
            ]
        ),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                "SharedObjCTestsUtils",
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
            ]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "NetworkingTestingUtils"
            ]
        ),
        .testTarget(
            name: "NavigationTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "Navigation",
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Swifter", package: "swifter"),
            ],
            resources: [
                // Xcode CodeSign build step fails for iOS target with "bundle format unrecognized, invalid, or unsuitable"
                // when the folder is named "Resources"
                //
                // https://stackoverflow.com/questions/29271548/code-sign-error-bundle-format-unrecognized-invalid-or-unsuitable
                .copy("Res")
            ],
            swiftSettings: [
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("WILLPERFORMCLIENTREDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_IS_REDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_MAIN_FRAME_NAVIGATION_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_PERFORMANCE_ENABLED", .when(platforms: [.macOS])),
                .define("TERMINATE_WITH_REASON_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED", .when(platforms: [.macOS])),
                .define("_SESSION_STATE_WITH_FILTER_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_AUTOPLAY_POLICY_ENABLED", .when(platforms: [.macOS])),
                .define("_ORIGINAL_DATA_AS_STRING_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "UserScriptTests",
            dependencies: [
                "BrowserServicesKitTestsUtils",
                "SharedObjCTestsUtils",
                "UserScript",
            ],
            resources: [
                .process("testUserScript.js"),
                .process("testLoadJSReplacements.js")
            ]
        ),
        .testTarget(
            name: "DuckAiDataStoreTests",
            dependencies: [
                "DuckAiDataStore",
                .product(name: "Persistence", package: "Persistence"),
                "SecureStorage",
            ]
        ),
        .testTarget(
            name: "PrivacyConfigTests",
            dependencies: [
                .product(name: "Persistence", package: "Persistence"),
                "PrivacyConfig",
                "PrivacyConfigTestsUtils"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "RemoteMessagingTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "BrowserServicesKitTestsUtils",
                "RemoteMessaging",
                "RemoteMessagingTestsUtils",
                .product(name: "Persistence", package: "Persistence"),
            ],
            resources: [
                .copy("Resources/remote-messaging-config-example.json"),
                .copy("Resources/remote-messaging-config-featured-items.json"),
                .copy("Resources/remote-messaging-config-malformed.json"),
                .copy("Resources/remote-messaging-config-metrics.json"),
                .copy("Resources/remote-messaging-config-unsupported-items.json"),
                .copy("Resources/remote-messaging-config.json"),
                .copy("Resources/remote-messaging-config-surfaces-default-values.json"),
                .copy("Resources/remote-messaging-config-surfaces-supported-values.json"),
                .copy("Resources/remote-messaging-config-surfaces-unsupported-values.json"),
                .copy("Resources/remote-messaging-config-surfaces-mixed-supported-and-unsupported-values.json"),
                .copy("Resources/remote-messaging-config-cards-list-items-with-rules.json"),
                .copy("Resources/remote-messaging-config-cards-list-items.json"),
                .copy("Resources/remote-messaging-config-placeholders.json"),
                .copy("Resources/remote-messaging-config-cards-list-items-with-sections.json"),
                .copy("Resources/Database_V1.sqlite"),
                .copy("Resources/Database_V1.sqlite-shm"),
                .copy("Resources/Database_V1.sqlite-wal"),
            ]
        ),
        .testTarget(
            name: "ConfigurationTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "Configuration",
                "NetworkingTestingUtils",
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
        .testTarget(
            name: "SyncDataProvidersTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "BookmarksTestsUtils",
                .product(name: "Persistence", package: "Persistence"),
                "SecureStorageTestsUtils",
                "SyncDataProviders",
            ]
        ),
        .testTarget(
            name: "SecureStorageTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "SecureStorage",
                "SecureStorageTestsUtils",
                .product(name: "PixelKit", package: "PixelKit")
            ]
        ),
        .testTarget(
            name: "PrivacyDashboardTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "PrivacyDashboard",
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "BrowserServicesKitTestsUtils",
            ]
        ),
        .testTarget(
            name: "SubscriptionTests",
            dependencies: [
                .product(name: "PixelKit", package: "PixelKit"),
                "SharedObjCTestsUtils",
                "Subscription",
                "SubscriptionTestingUtilities",
                "NetworkingTestingUtils",
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
        .testTarget(
            name: "DuckPlayerTests",
            dependencies: [
                "BrowserServicesKitTestsUtils",
                "DuckPlayer",
                "PrivacyConfigTestsUtils",
                "SharedObjCTestsUtils",
            ]
        ),

        .testTarget(
            name: "MaliciousSiteProtectionTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "Networking",
                "NetworkingTestingUtils",
                "MaliciousSiteProtection",
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            resources: [
                .copy("Resources/phishingHashPrefixes.json"),
                .copy("Resources/phishingFilterSet.json"),
            ]
        ),
        .testTarget(
            name: "PixelExperimentKitTests",
            dependencies: [
                "BloomFilterWrapper",
                "BrowserServicesKit",
                "SharedObjCTestsUtils",
                "PixelExperimentKit",
                "Configuration",
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "Navigation",
                "SecureStorage",
                "Subscription",
                "UserScript",
            ]
        ),
        .testTarget(
            name: "SpecialErrorPagesTests",
            dependencies: [
                "BrowserServicesKitTestsUtils",
                "SharedObjCTestsUtils",
                "SpecialErrorPages"
            ]
        ),
        .testTarget(
            name: "BrokenSitePromptTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "BrokenSitePrompt"
            ]
        ),
        .testTarget(
            name: "PageRefreshMonitorTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "PageRefreshMonitor"
            ]
        ),
        .testTarget(
            name: "PrivacyStatsTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "PrivacyStats",
            ]
        ),
        .testTarget(
            name: "AutoconsentStatsTests",
            dependencies: [
                "SharedObjCTestsUtils",
                "AutoconsentStats",
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
