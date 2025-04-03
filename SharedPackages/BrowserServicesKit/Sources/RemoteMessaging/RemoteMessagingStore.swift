//
//  RemoteMessagingStore.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import CoreData
import BrowserServicesKit
import Persistence
import os.log

public enum RemoteMessagingStoreError: Error {
    case saveConfigFailed
    case updateMessageShownFailed
    case updateMessageStatusFailed
}

public final class RemoteMessagingStore: RemoteMessagingStoring {

    public struct Notifications {
        static public let remoteMessagesDidChange = Notification.Name("com.duckduckgo.app.RemoteMessagesDidChange")
    }

    enum RemoteMessageStatus: Int16 {
        case scheduled
        case dismissed
        case done
    }

    public enum Constants {
        /// Identifier for a managed context used for saving data to the store
        public static let privateContextName = "RemoteMessaging"
        /// Identifier for a managed context used for read operations on the store
        public static let privateReadOnlyContextName = "RemoteMessagingFetching"
    }

    let database: CoreDataDatabase
    /**
     * This is a long-lived context, used for saving data to the store.
     *
     * All calls to this context are asynchronous to ensure that the code
     * is deadlock-free. A single context instance is used in order to avoid
     * merge conflicts.
     *
     * Read operations on the store use local context instances created on demand.
     */
    let context: NSManagedObjectContext
    let notificationCenter: NotificationCenter
    let remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding

    public init(
        database: CoreDataDatabase,
        notificationCenter: NotificationCenter = .default,
        errorEvents: EventMapping<RemoteMessagingStoreError>?,
        remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding
    ) {
        self.database = database
        self.notificationCenter = notificationCenter
        self.errorEvents = errorEvents
        self.remoteMessagingAvailabilityProvider = remoteMessagingAvailabilityProvider
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)

        featureFlagDisabledCancellable = remoteMessagingAvailabilityProvider.isRemoteMessagingAvailablePublisher
            .filter { !$0 }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                guard fetchScheduledRemoteMessage() != nil else {
                    return
                }
                Task {
                    await self.deleteScheduledMessages()
                }
            }
    }

    public func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) async {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            Logger.remoteMessaging.debug("Remote messaging feature flag is disabled, skipping saving processed version: \(processorResult.version)")
            return
        }
        Logger.remoteMessaging.debug("Remote messaging config - save processed version: \(processorResult.version)")

        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                storeRemoteMessagingConfig(with: processorResult.version, in: context)

                if let remoteMessage = processorResult.message {
                    addOrUpdate(remoteMessage: remoteMessage, in: context)
                } else {
                    markScheduledMessagesAsDone(in: context)
                }
                deleteNotShownDoneMessages(in: context)

                do {
                    try context.save()
                    notificationCenter.post(name: Notifications.remoteMessagesDidChange, object: nil)
                } catch {
                    errorEvents?.fire(.saveConfigFailed, error: error)
                    Logger.remoteMessaging.error("Failed to update remote messages: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    private func deleteScheduledMessages() async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                invalidateRemoteMessagingConfigs(in: context)
                markScheduledMessagesAsDone(in: context)
                deleteNotShownDoneMessages(in: context)

                do {
                    try context.save()
                    notificationCenter.post(name: Notifications.remoteMessagesDidChange, object: nil)
                } catch {
                    errorEvents?.fire(.saveConfigFailed, error: error)
                    Logger.remoteMessaging.error("Failed to updare remote messages: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    private let errorEvents: EventMapping<RemoteMessagingStoreError>?
    private var featureFlagDisabledCancellable: AnyCancellable?
}

// MARK: - RemoteMessagingConfigManagedObject Public Interface

extension RemoteMessagingStore {

    public func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return nil
        }

        var config: RemoteMessagingConfig?
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateReadOnlyContextName)
        context.performAndWait {
            let fetchRequest = RemoteMessagingConfigManagedObject.fetchRequest()
            fetchRequest.fetchLimit = 1
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "version", ascending: false)]

            guard let results = try? context.fetch(fetchRequest) else {
                return
            }
            if let remoteMessagingConfigManagedObject = results.first {
                config = RemoteMessagingConfig(remoteMessagingConfigManagedObject)
            }
        }

        return config
    }

}

// MARK: - RemoteMessagingConfigManagedObject Private Interface

extension RemoteMessagingStore {

    private func storeRemoteMessagingConfig(with version: Int64, in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<RemoteMessagingConfigManagedObject> = RemoteMessagingConfigManagedObject.fetchRequest()
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %lld", #keyPath(RemoteMessagingConfigManagedObject.version), version)

        if let results = try? context.fetch(fetchRequest), let result = results.first {
            result.evaluationTimestamp = Date()
            result.invalidate = false
        } else {
            let remoteMessagingConfigManagedObject = RemoteMessagingConfigManagedObject(context: context)
            remoteMessagingConfigManagedObject.version = NSNumber(value: version)
            remoteMessagingConfigManagedObject.evaluationTimestamp = Date()
            remoteMessagingConfigManagedObject.invalidate = false
        }
    }

    private func invalidateRemoteMessagingConfigs(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<RemoteMessagingConfigManagedObject> = RemoteMessagingConfigManagedObject.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false

        guard let results = try? context.fetch(fetchRequest) else { return }
        results.forEach { $0.invalidate = true }
    }
}

// MARK: - RemoteMessageManagedObject Public Interface

extension RemoteMessagingStore {

    public func fetchScheduledRemoteMessage() -> RemoteMessageModel? {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return nil
        }

        var scheduledRemoteMessage: RemoteMessageModel?
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateReadOnlyContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %i", RemoteMessageStatus.scheduled.rawValue)
            fetchRequest.returnsObjectsAsFaults = false

            guard let results = try? context.fetch(fetchRequest) else { return }

            for remoteMessageManagedObject in results {
                guard let message = remoteMessageManagedObject.message,
                      let remoteMessage = RemoteMessageMapper.fromString(message),
                      let id = remoteMessageManagedObject.id
                else {
                    continue
                }

                scheduledRemoteMessage = RemoteMessageModel(
                    id: id,
                    content: remoteMessage.content,
                    matchingRules: [],
                    exclusionRules: [],
                    isMetricsEnabled: remoteMessage.isMetricsEnabled
                )
                break
            }
        }
        return scheduledRemoteMessage
    }

    public func hasShownRemoteMessage(withID id: String) -> Bool {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return false
        }

        var shown: Bool = true
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateReadOnlyContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.fetchLimit = 1
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)

            guard let results = try? context.fetch(fetchRequest) else { return }

            if let result = results.first {
                shown = result.shown
            }
        }
        return shown
    }

    public func fetchShownRemoteMessageIDs() -> [String] {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return []
        }

        var dismissedMessageIds: [String] = []
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateReadOnlyContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "%K == YES", #keyPath(RemoteMessageManagedObject.shown))
            fetchRequest.returnsObjectsAsFaults = false

            do {
                let results = try context.fetch(fetchRequest)
                dismissedMessageIds = results.compactMap { $0.id }
            } catch {
                Logger.remoteMessaging.error("Failed to fetch shown remote messages: \(error.localizedDescription, privacy: .public)")
            }
        }
        return dismissedMessageIds
    }

    public func dismissRemoteMessage(withID id: String) async {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return
        }

        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                updateRemoteMessage(withID: id, toStatus: .dismissed, in: context)
                invalidateRemoteMessagingConfigs(in: context)

                do {
                    try context.save()
                } catch {
                    errorEvents?.fire(.updateMessageStatusFailed, error: error)
                    Logger.remoteMessaging.error("Error saving updateMessageStatus")
                }
                continuation.resume()
            }
        }
    }

    public func fetchDismissedRemoteMessageIDs() -> [String] {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return []
        }

        var dismissedMessageIds: [String] = []
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateReadOnlyContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %i", RemoteMessageStatus.dismissed.rawValue)
            fetchRequest.returnsObjectsAsFaults = false

            do {
                let results = try context.fetch(fetchRequest)
                dismissedMessageIds = results.compactMap { $0.id }
            } catch {
                Logger.remoteMessaging.error("Failed to fetch dismissed remote messages: \(error.localizedDescription, privacy: .public)")
            }
        }
        return dismissedMessageIds
    }

    public func updateRemoteMessage(withID id: String, asShown shown: Bool) async {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return
        }

        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
                fetchRequest.predicate = NSPredicate(
                    format: "%K == %@ AND %K == %d",
                    #keyPath(RemoteMessageManagedObject.id), id,
                    #keyPath(RemoteMessageManagedObject.shown), !shown
                )

                do {
                    guard let message = try context.fetch(fetchRequest).first else {
                        continuation.resume()
                        return
                    }
                    message.shown = shown
                    try context.save()
                } catch {
                    errorEvents?.fire(.updateMessageShownFailed, error: error)
                    Logger.remoteMessaging.error("Failed to save message update as shown")
                }
                continuation.resume()
            }
        }
    }

    public func resetRemoteMessages() async {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return
        }

        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                context.deleteAll(entityDescriptions: [
                    RemoteMessageManagedObject.entity(in: context),
                    RemoteMessagingConfigManagedObject.entity(in: context)
                ])

                do {
                    try context.save()
                } catch {
                    Logger.remoteMessaging.error("Failed to reset remote messages")
                }
                continuation.resume()
            }
        }
        notificationCenter.post(name: Notifications.remoteMessagesDidChange, object: nil)
    }
}

// MARK: - RemoteMessageManagedObject Private Interface

extension RemoteMessagingStore {

    private func addOrUpdate(remoteMessage: RemoteMessageModel, in context: NSManagedObjectContext) {
        if let scheduledRemoteMessage = RemoteMessageUtils.fetchScheduledRemoteMessage(in: context), scheduledRemoteMessage.id == remoteMessage.id {
            scheduledRemoteMessage.message = RemoteMessageMapper.toString(remoteMessage) ?? ""
        } else {
            markScheduledMessagesAsDone(in: context)

            let remoteMessageManagedObject = RemoteMessageUtils.fetchRemoteMessage(with: remoteMessage.id, in: context)
            ?? RemoteMessageManagedObject(context: context)

            remoteMessageManagedObject.message = RemoteMessageMapper.toString(remoteMessage) ?? ""
            remoteMessageManagedObject.status = NSNumber(value: RemoteMessageStatus.scheduled.rawValue)

            if remoteMessageManagedObject.isInserted {
                remoteMessageManagedObject.id = remoteMessage.id
                remoteMessageManagedObject.shown = false
            }
        }
    }

    private func updateRemoteMessage(withID id: String, toStatus status: RemoteMessageStatus, in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        fetchRequest.returnsObjectsAsFaults = false

        guard let results = try? context.fetch(fetchRequest) else { return }

        results.forEach { $0.status = NSNumber(value: status.rawValue) }
    }

    private func markScheduledMessagesAsDone(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "%K == %i",
            #keyPath(RemoteMessageManagedObject.status),
            RemoteMessageStatus.scheduled.rawValue
        )

        let messages = try? context.fetch(fetchRequest)
        messages?.forEach { message in
            message.status = NSNumber(value: RemoteMessageStatus.done.rawValue)
        }
    }

    private func deleteNotShownDoneMessages(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "%K == %i AND %K == NO",
            #keyPath(RemoteMessageManagedObject.status),
            RemoteMessageStatus.done.rawValue,
            #keyPath(RemoteMessageManagedObject.shown)
        )

        let results = try? context.fetch(fetchRequest)
        results?.forEach {
            context.delete($0)
        }
    }
}

// MARK: - MessageMapper

private struct RemoteMessageMapper {

    static func toString(_ remoteMessage: RemoteMessageModel?) -> String? {
        guard let message = remoteMessage,
              let encodedData = try? JSONEncoder().encode(message),
              let jsonString = String(data: encodedData, encoding: .utf8) else { return nil }
        return jsonString
    }

    static func fromString(_ payload: String) -> RemoteMessageModel? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RemoteMessageModel.self, from: data)
    }
}
