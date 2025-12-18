//
//  QuitSurveyPixels.swift
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

import PixelKit

enum QuitSurveyPixelName: String {
    case quitSurveyShown = "quit-survey-shown"
    case quitSurveyThumbsUp = "quit-survey-thumbs-up"
    case quitSurveyThumbsDown = "quit-survey-thumbs-down"
    case quitSurveyThumbsDownSubmission = "quit-survey-reasons-submission"
    case quitSurveyReturnUser = "quit-survey-reasons-return"

}

enum QuitSurveyPixels: PixelKitEvent {
    private static let reasonsKey = "reasons"

    case quitSurveyShown
    case quitSurveyThumbsUp
    case quitSurveyThumbsDown
    case quitSurveyThumbsDownSubmission(reasons: String)
    case quitSurveyReturnUser(reasons: String)

    var name: String {
        switch self {
        case .quitSurveyShown:
            return QuitSurveyPixelName.quitSurveyShown.rawValue
        case .quitSurveyThumbsUp:
            return QuitSurveyPixelName.quitSurveyThumbsUp.rawValue
        case .quitSurveyThumbsDown:
            return QuitSurveyPixelName.quitSurveyThumbsDown.rawValue
        case .quitSurveyThumbsDownSubmission:
            return QuitSurveyPixelName.quitSurveyThumbsDownSubmission.rawValue
        case .quitSurveyReturnUser:
            return QuitSurveyPixelName.quitSurveyReturnUser.rawValue
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .quitSurveyShown, .quitSurveyThumbsUp, .quitSurveyThumbsDown:
            return nil
        case let .quitSurveyThumbsDownSubmission(reasons), let .quitSurveyReturnUser(reasons):
            return [QuitSurveyPixels.reasonsKey: reasons]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}
