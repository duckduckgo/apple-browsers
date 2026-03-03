//
//  SparkleUpdateMenuItemFactory.swift
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

import AppUpdaterShared
import Cocoa

final class SparkleUpdateMenuItemFactory {

    static func menuItem(for controller: any SparkleUpdateControlling) -> NSMenuItem {

        let title: String

        if controller.isAtRestartCheckpoint {
            title = UserText.updateReadyMenuItem
        } else {
            title = UserText.updateNewVersionAvailableMenuItem
        }

        let item = NSMenuItem(title: title)
        item.target = controller
        item.action = #selector(SparkleUpdateControllerObjC.runUpdateFromMenuItem)
        item.image = NSImage.updateMenuItemIcon
        return item
    }

}
