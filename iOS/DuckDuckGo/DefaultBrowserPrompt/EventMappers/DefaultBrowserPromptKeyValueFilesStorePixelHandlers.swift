//
//  DefaultBrowserPromptKeyValueFilesStorePixelHandlers.swift
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
import class Common.EventMapping
import Core

enum DefaultBrowserPromptKeyValueFilesStorePixelHandlers {

    static let userActivityDebugPixelHandler = EventMapping<DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent> { event, error, _, _ in
        let pixelEvent: Pixel.Event
        switch event {
        case .failedToRetrieveActivity:
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Retrieve Current Activity: \(error)")
            pixelEvent = .debugDefaultBrowserPromptFailedToRetrieveCurrentActivity
        case .failedToSaveActivity:
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Save Current Activity: \(error)")
            pixelEvent = .debugDefaultBrowserPromptFailedToSaveCurrentActivity
        }
        DailyPixel.fireDailyAndCount(pixel: pixelEvent, error: error)
    }

    static let promptTypeDebugPixelHandler = EventMapping<DefaultBrowserPromptActivityKeyValueFilesStore.DebugEvent> { event, _, _, _ in
        switch event {
        case let .failedToRetrieveValue(.lastModalShownDate(error)):
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Retrieve Last Modal Shown Date: \(error)")
            DailyPixel.fireDailyAndCount(pixel: .debugDefaultBrowserPromptFailedToRetrieveLastModalShownDate, error: error)
        case let .failedToSaveValue(.lastModalShownDate(error)):
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Save Last Modal Shown Date: \(error)")
            DailyPixel.fireDailyAndCount(pixel: .debugDefaultBrowserPromptFailedToSaveLastModalShownDate, error: error)
        case let .failedToRetrieveValue(.modalShownOccurrences(error)):
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Retrieve Modal Shown Occurrences: \(error)")
            DailyPixel.fireDailyAndCount(pixel: .debugDefaultBrowserPromptFailedToRetrieveModalShownOccurrences, error: error)
        case let .failedToSaveValue(.modalShownOccurrences(error)):
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Save Modal Shown Occurrences: \(error)")
            DailyPixel.fireDailyAndCount(pixel: .debugDefaultBrowserPromptFailedToSaveModalShownOccurrences, error: error)
        case let .failedToRetrieveValue(.permanentlyDismissPrompt(error)):
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Retrieve Permanently Dismissed Prompt: \(error)")
            DailyPixel.fireDailyAndCount(pixel: .debugDefaultBrowserPromptFailedToRetrievePermanentlyDismissedPrompt, error: error)
        case let .failedToSaveValue(.permanentlyDismissPrompt(error)):
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Save Permanently Dismissed Prompt: \(error)")
            DailyPixel.fireDailyAndCount(pixel: .debugDefaultBrowserPromptFailedToSavePermanentlyDismissedPrompt, error: error)
        }
    }

    static let userTypeDebugPixelHandler = EventMapping<DefaultBrowserPromptUserTypeStore.DebugEvent> { event, error, _, _ in
        let pixelEvent: Pixel.Event
        switch event {
        case .failedToRetrieveUserType:
            Logger.defaultBrowserPrompt.error("[Default Browser Prompt] - Failed to Retrieve Default Browser Prompt User Type. Reason: \(error)")
            pixelEvent = .debugDefaultBrowserPromptFailedToRetrieveUserType
        case .failedToSaveUserType:
            Logger.defaultBrowserPrompt.error("[Default Browser Prompt] - Failed to Save Default Browser Prompt User Type. Reason: \(error)")
            pixelEvent = .debugDefaultBrowserPromptFailedToSaveUserType
        }
        DailyPixel.fireDailyAndCount(pixel: pixelEvent, error: error)
    }

}
