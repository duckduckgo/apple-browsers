//
//  Terminating.swift
//  DuckDuckGo
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

import UIKit.UIApplication
import Core

enum TerminationError: Error {

    case database(DatabaseError)
    case bookmarksDatabase(Error)
    case historyDatabase(Error)
    case keyValueFileStore(AppKeyValueFileStoreService.Error)
    case tabsPersistence(TabsPersistenceError)

}

private enum TerminationReason {

    case insufficientDiskSpace
    case unrecoverableState

}

private enum TerminationMode {

    case immediately(debugMessage: String)
    case afterAlert(reason: TerminationReason)

}

/// Handles critical launch-time errors and terminates the app appropriately.
///
/// This is used when a fatal error is thrown during app startup (e.g. from the `Launching` class).
/// It categorizes the error, reports it via a pixel, and either:
/// - Terminates immediately, or
/// - Shows a user-facing alert before termination (e.g. for disk space issues).
///
/// Unhandled errors result in a generic crash and pixel.
///
struct Terminating: TerminatingHandling {

    private let application: UIApplication

    init(error: Error, application: UIApplication = UIApplication.shared) {
        Logger.lifecycle.info("Terminating: \(#function)")

        self.application = application

        let mode: TerminationMode
        let pixel: Pixel.Event
        var errorToReport: Error?
        var additionalParams: [String: String] = [:]

        guard let error = error as? TerminationError else {
            DailyPixel.fireDailyAndCount(pixel: .appDidTerminateWithUnhandledError, error: error)
            Thread.sleep(forTimeInterval: 1)
            fatalError("Unhandled error: \(error)")
        }

        switch error {
        case .database(let error):
            additionalParams = [
                PixelParameters.applicationState: "\(application.applicationState.rawValue)",
                PixelParameters.dataAvailability: "\(application.isProtectedDataAvailable)"
            ]
            switch error {
            case .container(let error):
                pixel = .dbContainerInitializationError
                errorToReport = error
                mode = .immediately(debugMessage: "DB container init failed: \(error.localizedDescription)")
            case .other(let error):
                pixel = .dbInitializationError
                errorToReport = error
                mode = error.isDiskFull ? .afterAlert(reason: .insufficientDiskSpace) : .immediately(debugMessage: "DB init failed: \(error.localizedDescription)")
            }
        case .bookmarksDatabase(let error):
            pixel = .bookmarksCouldNotLoadDatabase
            errorToReport = error
            mode = error.isDiskFull ? .afterAlert(reason: .insufficientDiskSpace) : .immediately(debugMessage: "Bookmarks DB init failed: \(error.localizedDescription)")
        case .historyDatabase(let error):
            pixel = .historyStoreLoadFailed
            errorToReport = error
            mode = .afterAlert(reason: error.isDiskFull ? .insufficientDiskSpace : .unrecoverableState)
        case .keyValueFileStore(let error):
            pixel = switch error {
            case .appSupportDirAccessError: .keyValueFileStoreSupportDirAccessError
            case .kvfsInitError: .keyValueFileStoreInitError
            }
            mode = .immediately(debugMessage: "KeyValueFileStore init failed: \(error)")
        case .tabsPersistence(let error):
            pixel = switch error {
            case .appSupportDirAccess: .tabsStoreSupportDirAccessError
            case .storeInit: .tabsStoreInitError
            }
            mode = .immediately(debugMessage: "TabsModelPersistence init failed: \(error)")
        }

        DailyPixel.fireDailyAndCount(pixel: pixel,
                                     pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                                     error: errorToReport,
                                     withAdditionalParameters: additionalParams)
        switch mode {
        case .immediately(let message):
            Thread.sleep(forTimeInterval: 1)
            fatalError(message)
        case .afterAlert(let reason):
            alertAndTerminate(with: reason)
        }
    }

    private func alertAndTerminate(with reason: TerminationReason) {
        let alertController: UIAlertController
        switch reason {
        case .insufficientDiskSpace:
            alertController = CriticalAlerts.makeInsufficientDiskSpaceAlert()
        case .unrecoverableState:
            alertController = CriticalAlerts.makePreemptiveCrashAlert()
        }

        let window = UIWindow.makeBlank()
        application.setWindow(window)
        window.rootViewController?.present(alertController, animated: true, completion: nil)
    }

}

private extension Error {

    var isDiskFull: Bool {
        let nsError = self as NSError
        if let underlyingError = nsError.userInfo["NSUnderlyingError"] as? NSError, underlyingError.code == 13 {
            return true
        } else if nsError.userInfo["NSSQLiteErrorDomain"] as? Int == 13 {
            return true
        }
        return false
    }

}
