//
//  SponsorBlockSegmentsProvider.swift
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

import CryptoKit
import Foundation
import os.log

/// Fetches skip segments from the SponsorBlock API (https://wiki.sponsor.ajay.app/w/API_Docs).
///
/// Lookups use a SHA-256 hash prefix of the video ID, so the server never sees the exact video.
/// Results are cached in memory and shared across tabs through `shared`.
public actor SponsorBlockSegmentsProvider {

    // Segments endpoint; the request URL is `<apiBaseURL>/<hash prefix>?categories=…&actionTypes=…`.
    public static let apiBaseURL = URL(string: "https://web-dew-1.duckduckgo.com/sponsorblock/v1/segments")!
    public static let shared = SponsorBlockSegmentsProvider()

    public typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    public struct Segment: Encodable, Equatable {
        public let start: Double
        public let end: Double
        public let category: String
        public let actionType: String
        public let uuid: String
        public let videoDuration: Double?
    }

    public struct Query: Hashable {
        public static let defaultCategories = ["sponsor"]
        public static let defaultActionTypes = ["skip"]

        public let videoID: String
        public let categories: [String]
        public let actionTypes: [String]

        public init(videoID: String,
                    categories: [String] = Self.defaultCategories,
                    actionTypes: [String] = Self.defaultActionTypes) throws {
            guard Self.isValidVideoID(videoID) else { throw ProviderError.invalidParams("videoID") }
            guard Self.isValidList(categories) else { throw ProviderError.invalidParams("categories") }
            guard Self.isValidList(actionTypes) else { throw ProviderError.invalidParams("actionTypes") }
            self.videoID = videoID
            self.categories = categories
            self.actionTypes = actionTypes
        }

        /// Validates params received from a web page. Only `videoID` is read; the page does not choose what it gets back.
        public init(params: Any) throws {
            guard let videoID = (params as? [String: Any])?["videoID"] as? String else {
                throw ProviderError.invalidParams("videoID")
            }
            try self.init(videoID: videoID)
        }

        static func isValidVideoID(_ videoID: String) -> Bool {
            // \A and \z, because ICU's `$` also matches before a trailing newline.
            videoID.range(of: #"\A[A-Za-z0-9_-]{11}\z"#, options: .regularExpression) != nil
        }

        static func isValidList(_ list: [String]) -> Bool {
            (1...20).contains(list.count) && list.allSatisfy { $0.range(of: #"\A[a-z_]{1,32}\z"#, options: .regularExpression) != nil }
        }
    }

    public enum ProviderError: LocalizedError {
        case invalidParams(String)
        case invalidResponse
        case httpStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidParams(let name): return "Invalid getSegments param: \(name)"
            case .invalidResponse: return "Invalid SponsorBlock response"
            case .httpStatus(let status): return "SponsorBlock request failed with HTTP status \(status)"
            }
        }
    }

    private struct CacheEntry {
        let segments: [Segment]
        let storedAt: Date
    }

    private let load: DataLoader
    private let now: () -> Date
    private let capacity: Int
    private let timeToLive: TimeInterval

    private var cache: [Query: CacheEntry] = [:]
    /// Least recently used first.
    private var recency: [Query] = []
    private var inFlight: [Query: Task<[Segment], Error>] = [:]

    public init(load: DataLoader? = nil,
                now: @escaping () -> Date = Date.init,
                capacity: Int = 50,
                timeToLive: TimeInterval = 30 * 60) {
        self.load = load ?? Self.makeEphemeralLoader()
        self.now = now
        self.capacity = capacity
        self.timeToLive = timeToLive
    }

    public func segments(for query: Query) async throws -> [Segment] {
        if let cached = cachedSegments(for: query) {
            Logger.sponsorBlock.debug("segments served from cache")
            return cached
        }
        if let task = inFlight[query] {
            Logger.sponsorBlock.debug("segments joined an in-flight request")
            return try await task.value
        }
        Logger.sponsorBlock.debug("segments fetched from the API")

        let load = self.load
        let task = Task { try await Self.fetchSegments(for: query, load: load) }
        inFlight[query] = task
        defer { inFlight[query] = nil }

        let segments = try await task.value
        store(segments, for: query)
        return segments
    }

    // MARK: - Cache

    private func cachedSegments(for query: Query) -> [Segment]? {
        guard let entry = cache[query] else { return nil }
        guard now().timeIntervalSince(entry.storedAt) < timeToLive else {
            cache[query] = nil
            recency.removeAll { $0 == query }
            return nil
        }
        recency.removeAll { $0 == query }
        recency.append(query)
        return entry.segments
    }

    private func store(_ segments: [Segment], for query: Query) {
        cache[query] = CacheEntry(segments: segments, storedAt: now())
        recency.removeAll { $0 == query }
        recency.append(query)
        while recency.count > capacity {
            cache[recency.removeFirst()] = nil
        }
    }

    // MARK: - Network

    static func fetchSegments(for query: Query, load: DataLoader) async throws -> [Segment] {
        // Never log the URL or the video ID: the hash prefix must not reach the logs.
        let (data, response) = try await load(URLRequest(url: try url(for: query)))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        Logger.sponsorBlock.debug("API responded with HTTP \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200: return try parseSegments(from: data, videoID: query.videoID)
        case 404: return []
        default: throw ProviderError.httpStatus(httpResponse.statusCode)
        }
    }

    static func hashPrefix(for videoID: String) -> String {
        let hex = SHA256.hash(data: Data(videoID.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(4))
    }

    static func url(for query: Query) throws -> URL {
        let base = apiBaseURL.appendingPathComponent(hashPrefix(for: query.videoID))
        let queryString = "categories=\(try encodedJSON(query.categories))&actionTypes=\(try encodedJSON(query.actionTypes))"
        guard let url = URL(string: base.absoluteString + "?" + queryString) else {
            throw ProviderError.invalidParams("url")
        }
        return url
    }

    /// JSON-encodes the list, then percent-encodes everything except RFC 3986 unreserved characters.
    private static func encodedJSON(_ list: [String]) throws -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let json = String(bytes: try JSONEncoder().encode(list), encoding: .utf8),
              let encoded = json.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw ProviderError.invalidParams("url")
        }
        return encoded
    }

    private struct VideoEntry: Decodable {
        let videoID: String?
        let segments: [RawSegment]?
    }

    private struct RawSegment: Decodable {
        let segment: [Double]?
        let UUID: String?
        let category: String?
        let actionType: String?
        let videoDuration: Double?
    }

    /// The response lists every video whose hash shares the prefix; keeps only the requested one.
    static func parseSegments(from data: Data, videoID: String) throws -> [Segment] {
        guard let entries = try? JSONDecoder().decode([VideoEntry].self, from: data) else {
            throw ProviderError.invalidResponse
        }
        let rawSegments = entries.first { $0.videoID == videoID }?.segments ?? []
        Logger.sponsorBlock.debug("API returned \(entries.count) videos for the hash prefix, \(rawSegments.count) raw segments for the requested one")
        return rawSegments.compactMap { raw -> Segment? in
            guard let times = raw.segment, times.count == 2, times[1] >= times[0],
                  let uuid = raw.UUID, let category = raw.category, let actionType = raw.actionType else {
                return nil
            }
            return Segment(start: times[0], end: times[1], category: category, actionType: actionType, uuid: uuid, videoDuration: raw.videoDuration)
        }
        .sorted { $0.start < $1.start }
    }

    private static func makeEphemeralLoader() -> DataLoader {
        let session = URLSession(configuration: makeSessionConfiguration())
        return { try await session.data(for: $0) }
    }

    /// No cookies in either direction and no cache, so requests carry nothing but the hash prefix.
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        return configuration
    }
}
