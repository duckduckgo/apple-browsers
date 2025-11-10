//
//  RemoteMessagingConfigDecoder.swift
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
@testable import RemoteMessaging

package enum RemoteMessagingConfigDecoder {

    package static func decodeAndMapJson(fileName: String, bundle: Bundle, supportedSurfacesForMessage: @escaping (RemoteMessageModelType) -> RemoteMessageSurfaceType = RemoteMessagingConfigDecoder.supportedSurfaces(for:)) throws -> RemoteConfigModel {
        let resourceURL = bundle.resourceURL!.appendingPathComponent(fileName, conformingTo: .json)
        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        let surveyMapper = MockRemoteMessageSurveyActionMapper()

        let config = JsonToRemoteConfigModelMapper.mapJson(remoteMessagingConfig: remoteMessagingConfig, surveyActionMapper: surveyMapper, supportedSurfacesForMessage: supportedSurfacesForMessage)
        return config
    }

    package static func supportedSurfaces(for messageType: RemoteMessageModelType) -> RemoteMessageSurfaceType {
        switch messageType {
        case .small, .medium, .bigSingleAction, .bigTwoAction, .promoSingleAction:
            return .newTabPage
        case .cardsList:
            return [.modal, .dedicatedTab]
        }
    }

}
