//
//  AddToDockVideoPresenter.swift
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
import SwiftUI

enum AddToDockVideoAction: String {
    case done
    case next
    case cancel

    enum Primary {
        case done
        case next

        var action: AddToDockVideoAction {
            switch self {
            case .done: return .done
            case .next: return .next
            }
        }
    }
}

@MainActor
protocol AddToDockVideoPresenting {
    @discardableResult
    func present(primaryAction: AddToDockVideoAction.Primary, completion: @escaping (AddToDockVideoAction) -> Void) -> Bool
}

@MainActor
extension AddToDockVideoPresenting {
    @discardableResult
    func present(primaryAction: AddToDockVideoAction.Primary) -> Bool {
        present(primaryAction: primaryAction) { _ in }
    }
}

@MainActor
final class AddToDockVideoPresenter: AddToDockVideoPresenting {

    private struct PresentedSheet {
        weak var parentWindow: NSWindow?
        let sheetWindow: NSWindow
        let completion: (AddToDockVideoAction) -> Void
    }

    private let windowProvider: () -> NSWindow?
    private let newWindowProvider: @MainActor () -> NSWindow?
    private var presentedSheet: PresentedSheet?

    init(windowProvider: @escaping () -> NSWindow? = { NSApp.mainWindow ?? NSApp.keyWindow },
         newWindowProvider: @escaping @MainActor () -> NSWindow? = { WindowsManager.openNewWindow() }) {
        self.windowProvider = windowProvider
        self.newWindowProvider = newWindowProvider
    }

    @discardableResult
    func present(primaryAction: AddToDockVideoAction.Primary, completion: @escaping (AddToDockVideoAction) -> Void) -> Bool {
        guard presentedSheet?.parentWindow == nil, let parentWindow = windowProvider() ?? newWindowProvider() else { return false }

        let sheetView = AddToDockVideoSheet(videoURL: DockPreferencesModel.demoVideoURL,
                                            videoSize: DockPreferencesModel.demoVideoSize,
                                            primaryAction: primaryAction,
                                            showsInstructions: true,
                                            isPresented: .constant(true),
                                            onAction: { [weak self] action in self?.handle(action) })
        let sheetWindow = NSWindow(contentViewController: NSHostingController(rootView: sheetView))

        presentedSheet = PresentedSheet(parentWindow: parentWindow,
                                        sheetWindow: sheetWindow,
                                        completion: completion)
        parentWindow.beginSheet(sheetWindow) { [weak self, weak sheetWindow] _ in
            guard let self, let sheetWindow, presentedSheet?.sheetWindow === sheetWindow else { return }
            presentedSheet = nil
        }
        return true
    }

    func handle(_ action: AddToDockVideoAction) {
        guard let presentedSheet else { return }
        self.presentedSheet = nil

        presentedSheet.parentWindow?.endSheet(presentedSheet.sheetWindow)
        presentedSheet.completion(action)
    }
}
