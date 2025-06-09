//
//  DuckPlayerUserScript.swift
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
import Common

struct DuckPlayerUserScript {

    struct Constants {
        static let locale = "locale"
        static let localeDefault = "en"
        static let pageType = "pageType"
        static let timestamp = "timestamp"
        static let mute = "mute"
        static let pause = "pause"
        static let enabled = "enabled"
        static let playbackPaused = "playbackPaused"
        static let featureName = "duckPlayerNative"
    }

    struct PageType {
        static let SERP = "SERP"
        static let YOUTUBE = "YOUTUBE"
        static let UNKNOWN = "UNKNOWN"
        static let NOCOOKIE = "NOCOOKIE"
    }

    struct FEEvents {
        static let onMediaControl = "onMediaControl"
        static let onSerpNotify = "onSerpNotify"
        static let onMuteAudio = "onMuteAudio"
        static let onUrlChanged = "onUrlChanged"
    }

    struct Handlers {
        static let initialSetup = "initialSetup"
        static let onCurrentTimeStamp = "onCurrentTimestamp"
        static let onYoutubeError = "onYoutubeError"
        static let onDuckPlayerFeatureReady = "onDuckPlayerFeatureReady"
        static let onDuckPlayerScriptsReady = "onDuckPlayerScriptsReady"
    }

    static func getPageType(url: URL?) -> String {
        guard let url = url, let host = url.host else { return PageType.UNKNOWN }
        
        switch host {
        case DuckPlayerSettingsDefault.OriginDomains.duckduckgo:
            return PageType.SERP
        case DuckPlayerSettingsDefault.OriginDomains.youtube,
             DuckPlayerSettingsDefault.OriginDomains.youtubeWWW,
             DuckPlayerSettingsDefault.OriginDomains.youtubeMobile:
            if url.isYoutubeWatch {
                return PageType.YOUTUBE
            } else {
                return PageType.UNKNOWN
            }
        case DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie,
             DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW:
            return PageType.NOCOOKIE
        default:
            return PageType.UNKNOWN
        }
    }
    
}
