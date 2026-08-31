//
//  SitePermissionsPixelHandler.swift
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

import Common
import PixelKit
import SitePermissions

final class SitePermissionsPixelHandler: EventMapping<SitePermissionsEvent> {

    init(pixelFiring: (any PixelFiring)? = PixelKit.shared) {
        super.init { event, _, _, _ in
            pixelFiring?.fire(SitePermissionsPixel(event), frequency: .standard)
        }
    }
}

private struct SitePermissionsPixel: PixelKit.Event {

    let name: String

    init(_ event: SitePermissionsEvent) {
        switch event {
        case .permissionDialogImpression(let type):
            name = "permission_dialog_impression_\(type.rawValue)"
        case .permissionDialogClick(let type, let selection):
            name = "permission_dialog_click_\(type.rawValue)_\(selection.rawValue)"
        case .permissionSystemPromptResult(let type, let result):
            name = "permission_system_prompt_result_\(type.rawValue)_\(result.rawValue)"
        case .permissionReminderDialog(let type, let action):
            name = "permission_reminder_dialog_\(type.rawValue)_\(action.rawValue)"
        case .permissionSystemSettingsOpened(let type):
            name = "permission_system_settings_opened_\(type.rawValue)"
        case .voiceSearchPermissionPrompt(let action):
            name = "voice_search_permission_prompt_\(action.rawValue)"
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: PixelKitNamePrefix { .none }
}
