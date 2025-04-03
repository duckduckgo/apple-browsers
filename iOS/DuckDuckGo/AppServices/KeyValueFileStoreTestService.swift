//
//  KeyValueFileStoreTestService.swift
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

import Persistence
import Foundation
import Common
import Core

final class KeyValueFileStoreTestService {

    let twoStepTest = KeyValueFileStoreTwoStepService()
    let asyncTest = KeyValueFileStoreAsyncService()
    let retryTest = KeyValueFileStoreRetryService()

    func onForeground() {
        twoStepTest.onForeground()
    }

    func onBackground() {
        twoStepTest.onBackground()
    }

}

final class KeyValueFileStoreTwoStepService {

    enum Event: Equatable {
        case appSupportDirAccessError
        case kvfsInitError
        case kvfsFirstAccess(success: Bool)
        case kvfsSecondAccess(firstAccessStatus: Bool, secondAccessStatus: Bool)
    }

    enum Constants {
        static let testKey = "TestKey"
        static let testValue = "TestValue"

        static let pixelSourceParam = "source"
    }

    let keyValueFilesStore: ThrowingKeyValueStoring?
    let eventHandling: EventMapping<Event>

    var initialSaveSucceeded: Bool = false
    var secondReadSucceeded: Bool?

    convenience init() {

        let eventHandling = EventMapping<Event>(mapping: { event, error, params, _ in
            switch event {

            case .appSupportDirAccessError:
                Pixel.fire(pixel: .keyValueFileStoreSupportDirAccessError)
            case .kvfsInitError:
                Pixel.fire(pixel: .keyValueFileStoreInitError, error: error)
            case .kvfsFirstAccess(success: let success):
                Pixel.fire(pixel: .keyValueFileStoreFirstAccess(success: success),
                           error: error)
            case .kvfsSecondAccess(firstAccessStatus: let firstAccessStatus, secondAccessStatus: let secondAccessStatus):
                Pixel.fire(pixel: .keyValueFileStoreSecondAccess(firstAccessStatus: firstAccessStatus,
                                                                 secondAccessStatus: secondAccessStatus),
                           error: error,
                           withAdditionalParameters: params ?? [:])
            }

        })

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            eventHandling.fire(.appSupportDirAccessError)
            self.init(keyValueFilesStoreFactory: { nil },
                      eventHandling: eventHandling)
            return
        }

        self.init(keyValueFilesStoreFactory: {
            return try KeyValueFileStore(location: appSupportDir, name: "AppKeyValueStore")
        }, eventHandling: eventHandling)
    }

    init(keyValueFilesStoreFactory: () throws -> ThrowingKeyValueStoring?,
         eventHandling: EventMapping<Event>) {
        self.eventHandling = eventHandling

        do {
            self.keyValueFilesStore = try keyValueFilesStoreFactory()
        } catch {
            eventHandling.fire(.kvfsInitError, error: error)
            self.keyValueFilesStore = nil
            return
        }

        guard let keyValueFilesStore = self.keyValueFilesStore else { return }

        do {
            try keyValueFilesStore.set(Constants.testValue, forKey: Constants.testKey)
            self.initialSaveSucceeded = true
            eventHandling.fire(.kvfsFirstAccess(success: true))
        } catch {
            eventHandling.fire(.kvfsFirstAccess(success: false), error: error)
        }
    }

    private func onInteraction(source: String) {
        guard let keyValueFilesStore = self.keyValueFilesStore,
              secondReadSucceeded == nil else { return }

        do {
            try keyValueFilesStore.set(Constants.testValue, forKey: Constants.testKey)
            self.secondReadSucceeded = true
            eventHandling.fire(.kvfsSecondAccess(firstAccessStatus: self.initialSaveSucceeded,
                                                 secondAccessStatus: true),
                               parameters: ["source": source])
        } catch {
            eventHandling.fire(.kvfsSecondAccess(firstAccessStatus: self.initialSaveSucceeded,
                                                 secondAccessStatus: false),
                               error: error)
        }
    }

    func onForeground() {
        onInteraction(source: "foreground")
    }

    func onBackground() {
        onInteraction(source: "background")
    }
}

final class KeyValueFileStoreRetryService {

    enum Event: Equatable {
        case appSupportDirAccessError
        case kvfsInitError
        case kvfsAccess(success: Bool, delay: Int)
    }

    enum Constants {
        static let testKey = "TestKey"
        static let testValue = "TestValue"
    }

    let keyValueFilesStore: ThrowingKeyValueStoring?
    let eventHandling: EventMapping<Event>

    convenience init() {

        let eventHandling = EventMapping<Event>(mapping: { event, error, _, _ in

            switch event {

            case .appSupportDirAccessError:
                Pixel.fire(pixel: .keyValueFileStoreRetryDirAccessError)
            case .kvfsInitError:
                Pixel.fire(pixel: .keyValueFileStoreRetryInitError, error: error)
            case .kvfsAccess(success: let success, delay: let delay):
                Pixel.fire(pixel: .keyValueFileStoreRetryAccess(success: success, delay: delay),
                           error: error)
            }
        })

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            eventHandling.fire(.appSupportDirAccessError)
            self.init(keyValueFilesStoreFactory: { nil },
                      eventHandling: eventHandling)
            return
        }

        self.init(keyValueFilesStoreFactory: {
            return try KeyValueFileStore(location: appSupportDir, name: "AppKeyValueStore2")
        }, eventHandling: eventHandling)
    }

    init(keyValueFilesStoreFactory: () throws -> ThrowingKeyValueStoring?,
         eventHandling: EventMapping<Event>) {
        self.eventHandling = eventHandling

        do {
            self.keyValueFilesStore = try keyValueFilesStoreFactory()
        } catch {
            eventHandling.fire(.kvfsInitError, error: error)
            self.keyValueFilesStore = nil
        }

        guard self.keyValueFilesStore != nil else { return }

        trySaving()
    }

    private func trySaving(delay: Int = 0) {
        do {
            try self.keyValueFilesStore?.set(Constants.testValue, forKey: Constants.testKey)
            eventHandling.fire(.kvfsAccess(success: true, delay: delay))
        } catch {
            eventHandling.fire(.kvfsAccess(success: false, delay: delay), error: error)

            let newDelay: Int
            if delay == 0 {
                newDelay = 1
            } else {
                newDelay = delay * 2
            }

            // Just 5 retries
            guard newDelay < 10 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + Double(newDelay)) {
                self.trySaving(delay: newDelay)
            }
        }
    }

}

final class KeyValueFileStoreAsyncService {

    enum Event: Equatable {
        case appSupportDirAccessError
        case kvfsInitError
        case kvfsAccess(success: Bool)
    }

    enum Constants {
        static let testKey = "TestKey"
        static let testValue = "TestValue"
    }

    let keyValueFilesStore: ThrowingKeyValueStoring?
    let eventHandling: EventMapping<Event>

    convenience init() {

        let eventHandling = EventMapping<Event>(mapping: { event, error, _, _ in

            switch event {

            case .appSupportDirAccessError:
                Pixel.fire(pixel: .keyValueFileStoreAsyncDirAccessError)
            case .kvfsInitError:
                Pixel.fire(pixel: .keyValueFileStoreAsyncInitError, error: error)
            case .kvfsAccess(success: let success):
                Pixel.fire(pixel: .keyValueFileStoreAsyncFirstAccess(success: success), error: error)
            }
        })

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            eventHandling.fire(.appSupportDirAccessError)
            self.init(keyValueFilesStoreFactory: { nil },
                      eventHandling: eventHandling)
            return
        }

        self.init(keyValueFilesStoreFactory: {
            return try KeyValueFileStore(location: appSupportDir, name: "AppKeyValueStore3")
        }, eventHandling: eventHandling)
    }

    init(keyValueFilesStoreFactory: () throws -> ThrowingKeyValueStoring?,
         eventHandling: EventMapping<Event>) {
        self.eventHandling = eventHandling

        do {
            self.keyValueFilesStore = try keyValueFilesStoreFactory()
        } catch {
            eventHandling.fire(.kvfsInitError, error: error)
            self.keyValueFilesStore = nil
        }

        guard let keyValueFilesStore = self.keyValueFilesStore else { return }

        Task {
            do {
                try keyValueFilesStore.set(Constants.testValue, forKey: Constants.testKey)
                eventHandling.fire(.kvfsAccess(success: true))
            } catch {
                eventHandling.fire(.kvfsAccess(success: false))
            }
        }
    }

}
