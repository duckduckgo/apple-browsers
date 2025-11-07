//
//  BundleExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public extension Bundle {

    enum Key {

        public static let name = kCFBundleNameKey as String
        public static let identifier = kCFBundleIdentifierKey as String
        public static let buildNumber = kCFBundleVersionKey as String
        public static let versionNumber = "CFBundleShortVersionString"
        public static let displayName = "CFBundleDisplayName"
        public static let executableName = kCFBundleExecutableKey as String
        public static let documentTypes = "CFBundleDocumentTypes"
        public static let typeExtensions = "CFBundleTypeExtensions"

        /// Custom key that may be added by the adhoc build workflow to append a suffix to the build version
        public static let alphaBuildSuffix = "DDG_ALPHA_BUILD_SUFFIX"
        /// Custom key that may be added by the build workflow to indicate a commit of the build
        public static let commitSHA = "DDG_COMMIT_SHA"

        public static let vpnMenuAgentBundleId = "AGENT_BUNDLE_ID"
        public static let vpnMenuAgentProductName = "AGENT_PRODUCT_NAME"

        public static let ipcAppGroup = "IPC_APP_GROUP"

        public static let dbpBackgroundAgentBundleId = "DBP_BACKGROUND_AGENT_BUNDLE_ID"
        public static let dbpBackgroundAgentProductName = "DBP_BACKGROUND_AGENT_PRODUCT_NAME"
    }

    var releaseVersionNumber: String? { infoDictionary?[Key.versionNumber] as? String }
    var displayName: String? { object(forInfoDictionaryKey: Key.displayName) as? String ?? name }
    var name: String? { object(forInfoDictionaryKey: Key.name) as? String }

    var buildNumber: String {
        // swiftlint:disable:next force_cast
        object(forInfoDictionaryKey: Key.buildNumber) as! String
    }

    var versionNumber: String? {
        object(forInfoDictionaryKey: Key.versionNumber) as? String
    }

    var vpnMenuAgentBundleId: String {
        guard let bundleID = object(forInfoDictionaryKey: Key.vpnMenuAgentBundleId) as? String else {
            fatalError("Info.plist is missing \(Key.vpnMenuAgentBundleId)")
        }
        return bundleID
    }

    var loginItemsURL: URL {
        bundleURL.appendingPathComponent("Contents/Library/LoginItems")
    }

    var vpnMenuAgentURL: URL {
        guard let productName = object(forInfoDictionaryKey: Key.vpnMenuAgentProductName) as? String else {
            fatalError("Info.plist is missing \(Key.vpnMenuAgentProductName)")
        }
        return loginItemsURL.appendingPathComponent(productName + ".app")
    }

    var dbpBackgroundAgentBundleId: String {
        guard let bundleID = object(forInfoDictionaryKey: Key.dbpBackgroundAgentBundleId) as? String else {
            fatalError("Info.plist is missing \(Key.dbpBackgroundAgentBundleId)")
        }
        return bundleID
    }

    var dbpBackgroundAgentURL: URL {
        guard let productName = object(forInfoDictionaryKey: Key.dbpBackgroundAgentProductName) as? String else {
            fatalError("Info.plist is missing \(Key.dbpBackgroundAgentProductName)")
        }
        return loginItemsURL.appendingPathComponent(productName + ".app")
    }

    func appGroup(bundle: BundleGroup) -> String {
        let appGroupName = bundle.appGroupKey
        guard let appGroup = object(forInfoDictionaryKey: appGroupName) as? String else {
            fatalError("Info.plist is missing \(appGroupName)")
        }
        return appGroup
    }

    var ipcAppGroupName: String {
        guard let appGroup = object(forInfoDictionaryKey: Key.ipcAppGroup) as? String else {
            fatalError("Info.plist is missing \(Key.ipcAppGroup)")
        }
        return appGroup
    }

    var isInApplicationsDirectory: Bool {
        let directoryPaths = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .localDomainMask, true)

        guard let applicationsPath = directoryPaths.first else {
            // Default to true to be safe. In theory this should always return a valid path and the else branch will never be run, but some app logic
            // depends on this check in order to allow users to proceed, so we should avoid blocking them in case this assumption is ever wrong.
            return true
        }

        let path = self.bundlePath
        return path.hasPrefix(applicationsPath)
    }

    var documentTypes: [[String: Any]] {
        infoDictionary?[Key.documentTypes] as? [[String: Any]] ?? []
    }

    var fileTypeExtensions: Set<String> {
        documentTypes.reduce(into: []) { $0.formUnion($1[Key.typeExtensions] as? [String] ?? []) }
    }

}

public enum BundleGroup {
    case netP
    case ipc
    case dbp
    case subs
    case appConfiguration

    public var appGroupKey: String {
        switch self {
        case .dbp:
            return "DBP_APP_GROUP"
        case .ipc:
            return "IPC_APP_GROUP"
        case .netP:
            return "NETP_APP_GROUP"
        case .subs:
            return "SUBSCRIPTION_APP_GROUP"
        case .appConfiguration:
            return "APP_CONFIGURATION_APP_GROUP"
        }
    }
}
