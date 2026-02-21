//
//  UpdateCycleProgress.swift
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

import Foundation
import PixelKit

public enum UpdateCycleProgress: CustomStringConvertible {
    public enum DoneReason: Int {
        case finishedWithNoError = 100
        case finishedWithNoUpdateFound = 101
        case pausedAtDownloadCheckpoint = 102
        case pausedAtRestartCheckpoint = 103
        case proceededToInstallationAtRestartCheckpoint = 104
        case dismissedWithNoError = 105
        case dismissingObsoleteUpdate = 106
    }

    case updateCycleNotStarted
    case updateCycleDidStart
    case updateCycleDone(DoneReason)
    case downloadDidStart
    case downloading(Double)
    case extractionDidStart
    case extracting(Double)
    case readyToInstallAndRelaunch
    case installationDidStart
    case installing
    case updaterError(Error)

    public static var `default` = UpdateCycleProgress.updateCycleNotStarted

    public var isDone: Bool {
        switch self {
        case .updateCycleDone: return true
        default: return false
        }
    }

    public var isIdle: Bool {
        switch self {
        case .updateCycleDone, .updateCycleNotStarted, .updaterError: return true
        default: return false
        }
    }

    public var isFailed: Bool {
        switch self {
        case .updaterError: return true
        default: return false
        }
    }

    public var description: String {
        switch self {
        case .updateCycleNotStarted: return "updateCycleNotStarted"
        case .updateCycleDidStart: return "updateCycleDidStart"
        case .updateCycleDone(let reason): return "updateCycleDone(\(reason.rawValue))"
        case .downloadDidStart: return "downloadDidStart"
        case .downloading(let percentage): return "downloading(\(percentage))"
        case .extractionDidStart: return "extractionDidStart"
        case .extracting(let percentage): return "extracting(\(percentage))"
        case .readyToInstallAndRelaunch: return "readyToInstallAndRelaunch"
        case .installationDidStart: return "installationDidStart"
        case .installing: return "installing"
        case .updaterError(let error): return "updaterError(\(error.localizedDescription))(\(error.pixelParameters))"
        }
    }
}
