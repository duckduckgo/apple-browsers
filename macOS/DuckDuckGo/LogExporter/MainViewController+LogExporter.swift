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

extension MainViewController {

    static var sheetWindow: NSWindow?

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
