//
//  UpdatePromptStageDebugMenu.swift
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

import AppKit
import AppUpdaterShared
import FoundationExtensions

/// `Debug → Updates → More Prominent Updates → Prompt Stage` submenu, for moving through the update prompt stages without waiting.
@MainActor
final class UpdatePromptStageDebugMenu: NSMenu {
    private let debugSettings = UpdatesDebugSettings()
    private let promptStageMenuItem = NSMenuItem(title: "")
    private let promptClockMenuItem = NSMenuItem(title: "")
    private let forcePromptStageMenu = NSMenu()
    private let movePromptClockMenu = NSMenu()

    private var promptStageTracker: UpdatePromptStageTracker? {
        Application.appDelegate.updateController?.updatePromptStageTracker
    }

    init() {
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Force Prompt Stage")
                .submenu(forcePromptStageMenu)
            NSMenuItem(title: "Move Prompt Clock To")
                .submenu(movePromptClockMenu)
            NSMenuItem(title: "Reset Prompt Clock", action: #selector(resetPromptClock))
                .targetting(self)
            NSMenuItem.separator()
            promptStageMenuItem
            promptClockMenuItem
        }

        movePromptClockMenu.buildItems {
            NSMenuItem(title: "First Prompt", action: #selector(movePromptClockToStage), representedObject: UpdatePromptStage.firstPrompt)
                .targetting(self)
            NSMenuItem(title: "1 Minute Before First Prompt", action: #selector(movePromptClockToMinuteBeforeStage), representedObject: UpdatePromptStage.firstPrompt)
                .targetting(self)
            NSMenuItem.separator()
            NSMenuItem(title: "Second Prompt", action: #selector(movePromptClockToStage), representedObject: UpdatePromptStage.secondPrompt)
                .targetting(self)
            NSMenuItem(title: "1 Minute Before Second Prompt", action: #selector(movePromptClockToMinuteBeforeStage), representedObject: UpdatePromptStage.secondPrompt)
                .targetting(self)
            NSMenuItem.separator()
            NSMenuItem(title: "Third Prompt", action: #selector(movePromptClockToStage), representedObject: UpdatePromptStage.thirdPrompt)
                .targetting(self)
            NSMenuItem(title: "1 Minute Before Third Prompt", action: #selector(movePromptClockToMinuteBeforeStage), representedObject: UpdatePromptStage.thirdPrompt)
                .targetting(self)
        }

        forcePromptStageMenu.buildItems {
            NSMenuItem(title: "Automatic", action: #selector(forcePromptStage), representedObject: nil)
                .targetting(self)
            NSMenuItem.separator()
            for stage in UpdatePromptStage.allCases {
                NSMenuItem(title: String(describing: stage), action: #selector(forcePromptStage), representedObject: stage)
                    .targetting(self)
            }
        }

        updateMenuItemsState()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        updateMenuItemsState()
    }

    @objc private func forcePromptStage(_ sender: NSMenuItem) {
        debugSettings.forcedUpdatePromptStage = sender.representedObject as? UpdatePromptStage
        promptStageTracker?.reevaluate()
        updateMenuItemsState()
    }

    @objc private func movePromptClockToStage(_ sender: NSMenuItem) {
        movePromptClock(sender, timeRemaining: 0)
    }

    @objc private func movePromptClockToMinuteBeforeStage(_ sender: NSMenuItem) {
        movePromptClock(sender, timeRemaining: .minutes(1))
    }

    private func movePromptClock(_ sender: NSMenuItem, timeRemaining: TimeInterval) {
        guard let stage = sender.representedObject as? UpdatePromptStage else { return }
        promptStageTracker?.moveClock(to: stage, timeRemaining: timeRemaining)
        updateMenuItemsState()
    }

    @objc private func resetPromptClock() {
        promptStageTracker?.resetClock()
        updateMenuItemsState()
    }

    private func updateMenuItemsState() {
        let forcedStage = debugSettings.forcedUpdatePromptStage
        for item in forcePromptStageMenu.items where !item.isSeparatorItem {
            item.state = item.representedObject as? UpdatePromptStage == forcedStage ? .on : .off
        }

        let stage = promptStageTracker.map { String(describing: $0.stage) } ?? "unavailable"
        promptStageMenuItem.title = "Prompt Stage: \(stage)\(forcedStage == nil ? "" : " (forced)")"
        promptStageMenuItem.isEnabled = false

        let clockStart = promptStageTracker?.clockStartDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "not running"
        promptClockMenuItem.title = "Prompt Day 0: \(clockStart)"
        promptClockMenuItem.isEnabled = false
    }
}
