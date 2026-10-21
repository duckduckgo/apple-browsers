//
//  StatusBarMenu.swift
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

import Foundation
import AppKit
import DataBrokerProtectionCore

public final class StatusBarMenu: NSObject {
    private let statusItem: NSStatusItem
    #if DEBUG
    private var idleCloseTask: Task<Void, Never>?
    #endif
    private let popover: StatusBarPopover

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = StatusBarPopover()
        super.init()

        setupStatusItem()
    }

    @objc
    @MainActor
    private func statusBarButtonTapped() {
        togglePopover()
    }

    private func setupStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.image = NSImage(systemSymbolName: NSImage.Name("person.crop.circle.badge.minus"), accessibilityDescription: nil)
        statusItem.button?.action = #selector(statusBarButtonTapped)
        statusItem.button?.sendAction(on: [.leftMouseUp])
    }

    // MARK: - Popover

    #if DEBUG
    @MainActor
    public func setLivePreviewContent(agentInterface: DataBrokerProtectionAgentManager) {
        popover.setLivePreviewContent(agentInterface: agentInterface)
        PIRLivePreview.shared.manualControlStarted = { [weak self] in
            if let frame = self?.popover.contentViewController?.view.window?.frame { PIRLivePreview.shared.anchorFrame = frame }
            self?.popover.close()
        }
        PIRLivePreview.shared.automationResumed = { [weak self] in self?.showPopover() }
        PIRLivePreview.shared.activityChanged = { [weak self] isActive in self?.livePreviewActivityChanged(isActive) }
        // Open on Needs you when the agent starts with opt-outs waiting for the user, such as after a demo seed.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let pending = try? agentInterface.assistedOptOuts(), !pending.isEmpty else { return }
            self?.showPopover()
        }
    }

    /// Jobs in one run start a few seconds apart, so wait before treating the run as finished.
    @MainActor
    private func livePreviewActivityChanged(_ isActive: Bool) {
        idleCloseTask?.cancel()
        idleCloseTask = nil
        guard !isActive else {
            showPopover()
            return
        }
        idleCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.popover.close()
        }
    }
    #endif

    @MainActor
    private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else {
            showPopover()
        }
    }

    @MainActor
    private func showPopover() {
        #if DEBUG
        guard !PIRLivePreview.shared.isManualControlActive else { return }
        #endif
        guard !popover.isShown, let button = statusItem.button else { return }
        statusItem.isVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        #if DEBUG
        if popover.behavior == .applicationDefined {
            popover.contentViewController?.view.window?.hidesOnDeactivate = false
            popover.contentViewController?.view.window?.level = .floating
        }
        #endif
        popover.contentViewController?.view.window?.makeKey()
        #if DEBUG
        PIRLivePreview.shared.anchorFrame = popover.contentViewController?.view.window?.frame
        #endif
    }

    // MARK: - Showing & Hiding the menu

    public func show() {
        statusItem.isVisible = true
    }

    public func hide() {
        statusItem.isVisible = false
    }
}
