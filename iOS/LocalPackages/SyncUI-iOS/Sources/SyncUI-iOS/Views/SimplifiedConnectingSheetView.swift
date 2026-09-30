//
//  SimplifiedConnectingSheetView.swift
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

import SwiftUI
import DesignResourcesKit

#if DEBUG
import PreviewSnapshots
import UIComponents
#endif

public struct SimplifiedConnectingSheetView: View {

    @ObservedObject public var model: SyncSettingsViewModel

    public init(model: SyncSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            switch model.connectingSheetPhase {
            case .syncAnotherDevice:
                SyncAnotherDevicePromptView(model: model)
            case .connecting(let isRecovery, let successDestination):
                SimplifiedConnectingContentView(
                    isRecovery: isRecovery,
                    isFinishing: successDestination != nil,
                    onAnimationFinished: { model.connectingAnimationDidFinish() }
                )
            case .waitingForOtherDevice:
                SimplifiedConnectingContentView(
                    isRecovery: false,
                    isFinishing: false,
                    isWaitingForOtherDevice: true,
                    onAnimationFinished: {}
                )
            case .success(let destination):
                SyncSuccessView(model: model, destination: destination)
            case .none:
                EmptyView()
            }
        }
    }
}

#if DEBUG
struct SimplifiedConnectingSheetView_Previews: PreviewProvider {

    enum State {
        case syncAnotherDevice
        case connecting
        case deviceConnected
        case waitingForOtherDevice
        case recovering
        case recoveryCompleted
    }

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Sync Another Device", state: .syncAnotherDevice),
            .init(name: "Connecting", state: .connecting),
            .init(name: "Device Connected", state: .deviceConnected, scope: .previews),
            .init(name: "Check Other Device", state: .waitingForOtherDevice, scope: .previews),
            .init(name: "Recovering", state: .recovering, scope: .previews),
            .init(name: "Recovery Completed", state: .recoveryCompleted, scope: .previews)
        ],
        configure: { state in
            SimplifiedConnectingSheetView(model: model(for: state))
                .applyRebranding()
        }
    )

    private static func model(for state: State) -> SyncSettingsViewModel {
        switch state {
        case .syncAnotherDevice:
            return .connectingSheetPreview(phase: .syncAnotherDevice(isConnecting: false))
        case .connecting:
            return .connectingSheetPreview(phase: .connecting(isRecovery: false))
        case .deviceConnected:
            return .connectingSheetPreview(phase: .success(.joiner(isRecovery: false)), autoRestoreProvider: .enabled)
        case .waitingForOtherDevice:
            return .connectingSheetPreview(phase: .waitingForOtherDevice)
        case .recovering:
            return .connectingSheetPreview(phase: .connecting(isRecovery: true))
        case .recoveryCompleted:
            return .connectingSheetPreview(phase: .success(.joiner(isRecovery: true)))
        }
    }
}
#endif
