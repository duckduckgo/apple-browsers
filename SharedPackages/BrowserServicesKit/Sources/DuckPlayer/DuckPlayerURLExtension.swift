//
//  DuckPlayerURLExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common

extension String {

    public var url: URL? {
        return URL(trimmedAddressBarString: self)
    }
}

extension URL {

    public static let duckPlayerHost: String = "player"

    /**
     * Returns the actual URL of the Private Player page.
     *
     * Depending on the use of simulated requests, it's either the custom scheme URL
     * (without simulated requests, macOS <12), or youtube-nocookie.com URL (macOS 12 and newer).
     * iOS 15+ supports simulated requests, so no need to check
     */
    public static func effectiveDuckPlayer(_ videoID: String, timestamp: String? = nil) -> URL {
        #if os(iOS)
            return youtubeNoCookie(videoID, timestamp: timestamp)
        #else
        if #available(macOS 12.0, *) {
            return youtubeNoCookie(videoID, timestamp: timestamp)
        } else {
            return duckPlayer(videoID, timestamp: timestamp)
        }
        #endif
    }

    public static func duckPlayer(_ videoID: String, timestamp: String? = nil) -> URL {
        let url = "\(NavigationalScheme.duck.rawValue)://player/\(videoID)".url!
        return url.addingTimestamp(timestamp)
    }

    public static func youtubeNoCookie(_ videoID: String, timestamp: String? = nil) -> URL {
        let url = "https://www.youtube-nocookie.com/embed/\(videoID)".url!
        return url.addingTimestamp(timestamp)
    }

    public static func youtube(_ videoID: String, timestamp: String? = nil) -> URL {
        #if os(iOS)
        let baseUrl = "https://m.youtube.com/watch?v=\(videoID)"
        #else
        let baseUrl = "https://www.youtube.com/watch?v=\(videoID)"
        #endif

        let url = URL(string: baseUrl)!
        return url.addingTimestamp(timestamp)
    }

    // NOTE:
    // On macOS, this has been moved to DuckURLSchemeHandler.swift
    // Which is yet to be implemented on iOS
    public var isDuckURLScheme: Bool {
        navigationalScheme == .duck
    }

    public var isYoutubeWatch: Bool {
        guard let host else { return false }
        return host.contains("youtube.com") && path == "/watch"
    }

    public var isYoutubeWatchMainPage: Bool {
        return isYoutubeWatch && fragment == nil
    }

    private var isYoutubeNoCookie: Bool {
        host == "www.youtube-nocookie.com" && pathComponents.count == 3 && pathComponents[safe: 1] == "embed"
    }

    /// Returns true only if the URL represents a playlist itself, i.e. doesn't have `index` query parameter
    public var isYoutubePlaylist: Bool {
        guard isYoutubeWatch, let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return false
        }

        let isPlaylistURL = components.queryItems?.contains(where: { $0.name == "list" }) == true &&
        components.queryItems?.contains(where: { $0.name == "v" }) == true &&
        components.queryItems?.contains(where: { $0.name == "index" }) == false

        return isPlaylistURL
    }

    /// Returns true if the URL represents a YouTube video, but not the playlist (playlists are not supported by Private Player)
    public var isYoutubeVideo: Bool {
        isYoutubeWatch && !isYoutubePlaylist
    }

    /// Attempts extracting video ID and timestamp from the URL. Works with all types of YouTube URLs.
    public var youtubeVideoParams: (videoID: String, timestamp: String?)? {
        if isDuckURLScheme {
            guard let components = URLComponents(string: absoluteString) else {
                return nil
            }
            let unsafeVideoID = components.path
            let timestamp = components.queryItems?.first(where: { $0.name == "t" })?.value
            return (unsafeVideoID.removingCharacters(in: .youtubeVideoIDNotAllowed), timestamp)
        }

        if isDuckPlayer {
            let unsafeVideoID = lastPathComponent
            let timestamp = getParameter(named: "t")
            return (unsafeVideoID.removingCharacters(in: .youtubeVideoIDNotAllowed), timestamp)
        }

        guard isYoutubeVideo,
              let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let unsafeVideoID = components.queryItems?.first(where: { $0.name == "v" })?.value
        else {
            return nil
        }

        let timestamp = components.queryItems?.first(where: { $0.name == "t" })?.value
        return (unsafeVideoID.removingCharacters(in: .youtubeVideoIDNotAllowed), timestamp)
    }

    /**
     * Returns true if a URL represents a Private Player URL.
     *
     * It primarily checks for `duck://player/` URL, but on macOS 12 and above (when using simulated requests),
     * the Duck Scheme URL is eventually replaced by `www.youtube-nocookie.com/embed/VIDEOID` URL so this
     * is checked too and this function returns `true` if any of the two is true on macOS 12.
     */
    public var isDuckPlayer: Bool {
        let isPrivatePlayer = isDuckURLScheme && host == Self.duckPlayerHost
        #if os(iOS)
            return isPrivatePlayer || isYoutubeNoCookie
        #else
        if #available(macOS 12.0, *) {
            return isPrivatePlayer || isYoutubeNoCookie
        } else {
            return isPrivatePlayer
        }
        #endif

    }

    public var isYoutube: Bool {
        guard let host else { return false }
        return host == "m.youtube.com" || host == "youtube.com" || host == "www.youtube.com"
    }

    public func addingWatchInYoutubeQueryParameter() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "embeds_referring_euri", value: "some_value"))
        components.queryItems = queryItems

        return components.url
    }

    public var hasWatchInYoutubeQueryParameter: Bool {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return false
        }

        for queryItem in queryItems where queryItem.name == "embeds_referring_euri" {
            return true
        }

        return false
    }

    /**
     * Returns true if the URL represents a YouTube video recommendation.
     *
     * Recommendations are shown at the end of the embedded video or while it's paused.
     */
    public var isYoutubeVideoRecommendation: Bool {
        guard isYoutubeVideo,
              let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let featureQueryParameter = components.queryItems?.first(where: { $0.name == "feature" })?.value
        else {
            return false
        }

        let recommendationFeatures = [ "emb_rel_end", "emb_rel_pause" ]

        return recommendationFeatures.contains(featureQueryParameter)
    }

    public var youtubeVideoID: String? {
        youtubeVideoParams?.videoID
    }

    func addingTimestamp(_ timestamp: String?) -> URL {
        guard let timestamp = timestamp,
              let regex = try? NSRegularExpression(pattern: "^(\\d+[smh]?)+$"),
              timestamp.matches(regex)
        else {
            return self
        }
        return appendingParameter(name: "t", value: timestamp)
    }
}

extension CharacterSet {
    public static let youtubeVideoIDNotAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").inverted
}
