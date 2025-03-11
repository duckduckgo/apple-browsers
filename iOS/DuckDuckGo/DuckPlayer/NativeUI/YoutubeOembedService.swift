//
//  YoutubeOembedService.swift
//  DuckDuckGo
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

public struct OEmbedResponse: Decodable {
    public let title: String
    public let authorName: String
    public let thumbnailUrl: String
    
    private enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case thumbnailUrl = "thumbnail_url"
    }
}

protocol YoutubeOembedService {
    func fetchMetadata(for videoID: String) async -> OEmbedResponse?
}

// Uses Youtube's oembed API to fetch video metadata
// See: https://oembed.com 
public final class DefaultYoutubeOembedService: YoutubeOembedService {

    public func fetchMetadata(for videoID: String) async -> OEmbedResponse? {
        do {
            let oembedURL = URL.youtubeOembed(videoID)
            let (data, _) = try await URLSession.shared.data(from: oembedURL)
            return try? JSONDecoder().decode(OEmbedResponse.self, from: data)
        } catch {
            return nil
        }
    }
}

extension URL {
    // Returns Youtube's oembed URL for a specific video ID
    public static func youtubeOembed(_ videoID: String) -> URL {
        let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json")!
        return url
    }

}
