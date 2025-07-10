//
//  AIChatRAGTool.swift
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

/// Supported AI Chat tools
/// https://dub.duckduckgo.com/duckduckgo/ddg/blob/b6c87a90c2722709dfe75063cba7f43243ce1d02/www-release/frontend/react/src/duck-chat/data/models-list.ts#L23-L30
public enum AIChatRAGTool: String, CaseIterable {
    case webSearch = "WebSearch"
    case newsSearch = "NewsSearch"
    case videosSearch = "VideosSearch"
    case localSearch = "LocalSearch"
    case relatedSearchTerms = "RelatedSearchTerms"
    case weatherForecast = "WeatherForecast"
}
