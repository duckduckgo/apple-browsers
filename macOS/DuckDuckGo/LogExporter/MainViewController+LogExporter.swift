//
//  MainViewController+LogExporter.swift
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
import AppKit
import SwiftUI
import DataBrokerProtection_macOS

extension MainViewController {

    static var sheetWindow: NSWindow?
    static var logMonitorWindowController: NSWindowController?

    @objc public func openLogMonitor(_ sender: NSMenuItem) {
        if MainViewController.logMonitorWindowController == nil {
            let viewController = DataBrokerLogMonitorViewController()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.contentViewController = viewController
            window.title = "Log Monitor"
            window.minSize = NSSize(width: 1000, height: 650)
            window.center()
            window.isReleasedWhenClosed = false

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainViewController.logMonitorWindowController = nil
            }

            MainViewController.logMonitorWindowController = NSWindowController(window: window)
        }

        MainViewController.logMonitorWindowController?.showWindow(self)
        MainViewController.logMonitorWindowController?.window?.makeKeyAndOrderFront(self)
    }

    @objc public func exportLogs(_ sender: NSMenuItem) {

        let exporterView = LogExporterView { result in

            if let sheet = MainViewController.sheetWindow {
                self.view.window?.endSheet(sheet)
            }

            if result.confirmed {
                Task {
                    do {
                        try await LogExporter.export(configuration: result)

                        let alert = NSAlert()
                        alert.messageText = "Logs exported on your Desktop..."

                        Task { @MainActor in
                            if let window = NSApp.mainWindow {
                                alert.beginSheetModal(for: window)
                            }
                        }
                    } catch {
                        await NSAlert(error: error).runModal()
                    }
                }
            } else {
                print("User cancelled")
            }
        }

        let hostingController = NSHostingController(rootView: exporterView)
        MainViewController.sheetWindow = NSWindow(contentViewController: hostingController)

        // Present as sheet
        if let sheetWindow = MainViewController.sheetWindow {
            self.view.window?.beginSheet(sheetWindow, completionHandler: nil)
        }
    }
}
