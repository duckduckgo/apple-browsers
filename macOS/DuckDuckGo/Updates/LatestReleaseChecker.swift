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
import Foundation

public enum LatestReleaseMetadataType {
    case macOSAppStore
}

public enum LatestReleaseError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case metadataNotFound

    public var errorDescription: String? {
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
}

public struct ReleaseMetadata: Codable {
    public let latestVersion: String
    public let buildNumber: String
    public let releaseDate: String
    public let isCritical: Bool

    public init(latestVersion: String, buildNumber: String, releaseDate: String, isCritical: Bool) {
        self.latestVersion = latestVersion
        self.buildNumber = buildNumber
        self.releaseDate = releaseDate
        self.isCritical = isCritical
    }

    enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case buildNumber = "build_number"
        case releaseDate = "release_date"
        case isCritical = "is_critical"
    }
}

private struct ReleaseMetadataCollector: Codable {
    let latestAppStoreVersion: ReleaseMetadata

    enum CodingKeys: String, CodingKey {
        case latestAppStoreVersion = "latest_appstore_version"
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

    public func getLatestReleaseAvailable(
        for metadataType: LatestReleaseMetadataType
    ) async throws -> ReleaseMetadata {
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

            let decoder = JSONDecoder()
            let metadata = try decoder.decode(ReleaseMetadataCollector.self, from: data)

            switch metadataType {
            case .macOSAppStore:
                return metadata.latestAppStoreVersion
            }
        } catch let error as DecodingError {
            throw LatestReleaseError.decodingError(error)
        } catch let error as LatestReleaseError {
            throw error
        } catch {
            throw LatestReleaseError.networkError(error)
        }
    }
}
