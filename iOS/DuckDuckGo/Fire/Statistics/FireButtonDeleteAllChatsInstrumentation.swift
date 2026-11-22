//
//  FireButtonDeleteAllChatsInstrumentation.swift
//  DuckDuckGo
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

import Core
import Foundation
import PixelKit

struct FireButtonDeleteAllChatsInstrumentation {
    let pixelFiring: (any PixelKitFiring)?

    init(pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func shown(layout: FireButtonDeleteAllChatsPixel.Layout, context: FireButtonDeleteAllChatsPixel.Context) {
        pixelFiring?.fire(FireButtonDeleteAllChatsPixel.shown(layout: layout, context: context))
    }

    func executed(layout: FireButtonDeleteAllChatsPixel.Layout, browsingMode: BrowsingMode, context: FireButtonDeleteAllChatsPixel.Context) {
        pixelFiring?.fire(FireButtonDeleteAllChatsPixel.executed(layout: layout, browsingMode: browsingMode, context: context), frequency: .dailyAndCount)
    }

    func countUnavailable(reason: NativeChatsReadFailure) {
        pixelFiring?.fire(FireButtonDeleteAllChatsPixel.countUnavailable(reason: reason), frequency: .dailyAndCount)
    }
}

enum FireButtonDeleteAllChatsPixel: PixelKit.Event {
    enum Layout: String {
        case withThisChat = "with_this_chat"
        case allChatsOnly = "all_chats_only"

        init(chatCount: Int) {
            self = chatCount == 1 ? .allChatsOnly : .withThisChat
        }
    }

    enum Context: String {
        case tab
        case contextual
    }

    case shown(layout: Layout, context: Context)
    case executed(layout: Layout, browsingMode: BrowsingMode, context: Context)
    case countUnavailable(reason: NativeChatsReadFailure)

    var standardParameters: [PixelKitStandardParameter]? { nil }
    var error: NSError? { nil }

    var name: String {
        switch self {
        case .shown: return "aichat_fire_delete-all-chats_shown"
        case .executed: return "aichat_fire_delete-all-chats_executed"
        case .countUnavailable: return "aichat_fire_delete-all-chats_count-unavailable"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .shown(let layout, let context):
            return ["layout": layout.rawValue, "context": context.rawValue]
        case .executed(let layout, let browsingMode, let context):
            return ["layout": layout.rawValue, PixelParameters.browsingMode: browsingMode.pixelParamValue, "context": context.rawValue]
        case .countUnavailable(let reason):
            return ["reason": reason.rawValue]
        }
    }
}
