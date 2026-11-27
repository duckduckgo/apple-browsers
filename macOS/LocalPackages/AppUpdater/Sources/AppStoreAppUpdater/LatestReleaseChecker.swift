//
//  LatestReleaseChecker.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import AppUpdaterShared
import BrowserServicesKit
import Common
import DDGError
import FoundationExtensions
import Foundation

public enum LatestReleaseError: DDGError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case metadataNotFound

    public var errorCode: Int {
        switch self {
        case .invalidURL: return 1
        case .networkError: return 2
        case .decodingError: return 3
        case .metadataNotFound: return 4
        }
    }

    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid release metadata URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode metadata: \(error.localizedDescription)"
        case .metadataNotFound:
            return "Release metadata not found"
        }
    }

    public static var errorDomain: String {
        "com.duckduckgo.LatestReleaseError"
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .networkError(let error): return error
        case .decodingError(let error): return error
        default: return nil
        }
    }

    public static func == (lhs: LatestReleaseError, rhs: LatestReleaseError) -> Bool {
        return lhs.errorCode == rhs.errorCode
    }
}

/// The App Store entries in the release metadata file.
public struct AppStoreReleases: Decodable {
    /// The release that has finished rolling out.
    public let latest: ReleaseMetadata

    /// The release that is rolling out, published when its rollout starts.
    public let available: ReleaseMetadata?

    enum CodingKeys: String, CodingKey {
        case latest = "latest_appstore_version"
        case available = "available_appstore_version"
    }

    public init(latest: ReleaseMetadata, available: ReleaseMetadata?) {
        self.latest = latest
        self.available = available
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decode(ReleaseMetadata.self, forKey: .latest)
        available = try? container.decodeIfPresent(ReleaseMetadata.self, forKey: .available)
    }

    /// The release to offer the user.
    ///
    /// Returns the available release if it was released at least `delay` ago and is newer than the latest
    /// release. Otherwise returns the latest release. The available release in the metadata shouldn't
    /// ever be older than the latest one, but if that were to happen this version check would prevent
    ///  users from being told there's no update.
    public func releaseToOffer(availableAfter delay: TimeInterval, now: Date) -> ReleaseMetadata {
        guard let available,
              Self.isRelease(available, newerThan: latest),
              let releaseDate = ISO8601DateFormatter().date(from: available.releaseDate),
              now >= releaseDate.addingTimeInterval(delay) else {
            return latest
        }
        return available
    }

    private static func isRelease(_ release: ReleaseMetadata, newerThan other: ReleaseMetadata) -> Bool {
        switch release.latestVersion.compare(other.latestVersion, options: .numeric) {
        case .orderedDescending: true
        case .orderedAscending: false
        case .orderedSame: release.buildNumber > other.buildNumber
        }
    }
}

public final class LatestReleaseChecker {
    private let baseURL: String?
    private let urlSession: URLSession
    private let debugSettings: UpdatesDebugSettings

    /// An explicitly supplied base URL takes precedence over the Debug menu override.
    public init(baseURL: String? = nil,
                urlSession: URLSession = .shared,
                debugSettings: UpdatesDebugSettings = UpdatesDebugSettings()) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.debugSettings = debugSettings
    }

    private var releaseMetadataURL: String {
        #if DEBUG
        let customBaseURL = baseURL ?? debugSettings.appStoreMetadataBaseURL
        #else
        let customBaseURL = baseURL
        #endif
        let resolvedURL = customBaseURL ?? "https://staticcdn.duckduckgo.com/macos-desktop-browser/"
        let separator = resolvedURL.hasSuffix("/") ? "" : "/"
        return resolvedURL + separator + "release_metadata.json"
    }

    public func getAppStoreReleases() async throws -> AppStoreReleases {
        guard let url = URL(string: releaseMetadataURL) else {
            throw LatestReleaseError.invalidURL
        }

        var request = URLRequest(url: url)
        #if DEBUG
        if baseURL == nil, debugSettings.appStoreMetadataBaseURL != nil {
            let appVersion = AppVersion()
            request.setValue(appVersion.versionNumber, forHTTPHeaderField: "X-DDG-Test-App-Version")
            request.setValue(appVersion.buildNumber, forHTTPHeaderField: "X-DDG-Test-App-Build")
        }
        #endif

        do {
            let (data, response) = try await urlSession.data(for: request)

            // Validate HTTP response
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                throw LatestReleaseError.networkError(URLError(.badServerResponse))
            }

            return try JSONDecoder().decode(AppStoreReleases.self, from: data)
        } catch let error as DecodingError {
            throw LatestReleaseError.decodingError(error)
        } catch let error as LatestReleaseError {
            throw error
        } catch {
            throw LatestReleaseError.networkError(error)
        }
    }
}
