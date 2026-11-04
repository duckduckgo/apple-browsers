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

    /// The available release once `delay` has passed since its release date, otherwise the latest release.
    public func releaseToOffer(availableAfter delay: TimeInterval, now: Date) -> ReleaseMetadata {
        guard let available,
              let releaseDate = ISO8601DateFormatter().date(from: available.releaseDate),
              now >= releaseDate.addingTimeInterval(delay) else {
            return latest
        }
        return available
    }
}

public final class LatestReleaseChecker {
    private let baseURL: String
    private let urlSession: URLSession

    public init(baseURL: String = "https://staticcdn.duckduckgo.com/macos-desktop-browser/",
                urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    private var releaseMetadataURL: String {
        return baseURL + "release_metadata.json"
    }

    public func getAppStoreReleases() async throws -> AppStoreReleases {
        guard let url = URL(string: releaseMetadataURL) else {
            throw LatestReleaseError.invalidURL
        }

        do {
            let (data, response) = try await urlSession.data(from: url)

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
