//
//  MockAVPictureInPictureController.swift
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

import AVKit

final class MockAVPictureInPictureController: AVPictureInPictureController {

    // MARK: - Delegate

    var backingDelegate: AVPictureInPictureControllerDelegate?

    override var delegate: (any AVPictureInPictureControllerDelegate)? {
        get { backingDelegate }
        set { backingDelegate = newValue }
    }

    // MARK: - isPictureInPictureSupported

    static var backingIsPictureInPictureSupported = true

    override class func isPictureInPictureSupported() -> Bool {
        backingIsPictureInPictureSupported
    }

    // MARK: - canStartPictureInPictureAutomaticallyFromInline

    var backingCanStartPictureInPictureAutomaticallyFromInline: Bool = false

    override var canStartPictureInPictureAutomaticallyFromInline: Bool {
        get { backingCanStartPictureInPictureAutomaticallyFromInline }
        set { backingCanStartPictureInPictureAutomaticallyFromInline = newValue }
    }

    // MARK: - isPictureInPictureActive

    var backingIsPictureInPictureActive: Bool = false

    override var isPictureInPictureActive: Bool { backingIsPictureInPictureActive }


    private(set) var didCallStopPictureInPicture = false

    // MARK: - stopPictureInPicture

    override func stopPictureInPicture() {
        didCallStopPictureInPicture = true
    }

}
