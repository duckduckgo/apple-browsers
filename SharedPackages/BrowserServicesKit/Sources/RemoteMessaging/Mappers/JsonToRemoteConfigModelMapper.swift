//
//  JsonToRemoteConfigModelMapper.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import os.log

struct JsonToRemoteConfigModelMapper {

    static func mapJson(remoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig,
                        surveyActionMapper: RemoteMessagingSurveyActionMapping) -> RemoteConfigModel {
        let remoteMessages = JsonToRemoteMessageModelMapper.maps(
            jsonRemoteMessages: remoteMessagingConfig.messages,
            surveyActionMapper: surveyActionMapper
        )
        Logger.remoteMessaging.debug("remoteMessages mapped = \(String(describing: remoteMessages), privacy: .public)")
        let rules = JsonToRemoteMessageModelMapper.maps(jsonRemoteRules: remoteMessagingConfig.rules)
        Logger.remoteMessaging.debug("rules mapped = \(String(describing: rules), privacy: .public)")
        return RemoteConfigModel(messages: remoteMessages, rules: rules)
    }

}
