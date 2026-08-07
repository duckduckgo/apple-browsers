//
//  QRunInBackgroundAssertion.swift
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

import UIKit

/// Based on: https://developer.apple.com/forums/thread/729335
///
/// Prevents the process from suspending by holding a `UIApplication` background
/// task assertion.
///
/// The assertion is released if:
///
/// * You explicitly release the assertion by calling ``release()``.
/// * There are no more strong references to the object and so it gets deinitialised.
/// * The system ‘calls in’ the assertion, in which case it calls the
///   ``systemDidReleaseAssertion`` closure, if set.
///
/// You should aim to explicitly release the assertion yourself, as soon as
/// you’ve completed the work that the assertion covers.

public final class QRunInBackgroundAssertion {

    /// The name used when creating the assertion.

    public let name: String

    public let application: UIApplication

    /// Called when the system releases the assertion itself.
    ///
    /// This is called on the main thread.
    ///
    /// To help avoid retain cycles, the object sets this to `nil` whenever the
    /// assertion is released.

    public var systemDidReleaseAssertion: (() -> Void)? {
        willSet { dispatchPrecondition(condition: .onQueue(.main)) }
    }

    private var taskID: UIBackgroundTaskIdentifier

    /// Creates an assertion with the given name.
    ///
    /// The name isn’t used by the system but it does show up in various logs so
    /// it’s important to choose one that’s meaningful to you.
    ///
    /// Must be called on the main thread.

    public init(name: String, application: UIApplication) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.name = name
        self.application = application
        self.systemDidReleaseAssertion = nil
        // Have to initialise `taskID` first so that I can capture a fully
        // initialised `self` in the expiration handler.  If the expiration
        // handler ran ／before／ I got a chance to set `self.taskID` to `t`,
        // things would end badly.  However, that can’t happen because I’m
        // running on the main thread — courtesy of the Dispatch precondition
        // above — and the expiration handler also runs on the main thread.
        self.taskID = .invalid
        let t = self.application.beginBackgroundTask(withName: name) {
            self.taskDidExpire()
        }
        self.taskID = t
    }

    /// Release the assertion.
    ///
    /// It’s safe to call this redundantly, that is, call it twice in a row or
    /// call it on an assertion that’s expired.
    ///
    /// Must be called on the main thread.

    public func release() {
        dispatchPrecondition(condition: .onQueue(.main))
        self.consumeValidTaskID { }
    }

    deinit {
        // We don’t check the main thread precondition because it’s hard to force the last object
        // reference to be released on the main thread.  However, it should be
        // safe to call through to `consumeValidTaskID(_:)` because no other
        // thread can be running inside this object (because that would have its
        // own retain on us).
        self.consumeValidTaskID { }
    }

    private func consumeValidTaskID(_ body: () -> Void) {
        guard self.taskID != .invalid else { return }
        self.application.endBackgroundTask(self.taskID)
        self.taskID = .invalid
        body()
        self.systemDidReleaseAssertion = nil
    }

    private func taskDidExpire() {
        dispatchPrecondition(condition: .onQueue(.main))
        self.consumeValidTaskID {
            self.systemDidReleaseAssertion?()
        }
    }
}
