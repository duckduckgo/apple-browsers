//
//  PasswordManagementItemModelTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import XCTest
import AppKit
import Common
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

final class PasswordManagementItemModelTests: XCTestCase {

    var isDirty = false
    var savedCredentials: SecureVaultModels.WebsiteCredentials?
    var deletedCredentials: SecureVaultModels.WebsiteCredentials?
    var urlMatcher = AutofillDomainNameUrlMatcher()
    var emailManager = EmailManager()
    var tld = Application.appDelegate.tld
    var urlSort = AutofillDomainNameUrlSort()

    override var allowedNonNilVariables: Set<String> {
        ["emailManager", "tld"]
    }

    func testWhenCredentialsAreSavedThenSaveIsRequested() {
        let model = PasswordManagementLoginModel(onSaveRequested: onSaveRequested,
                                                 onDeleteRequested: onDeleteRequested,
                                                 urlMatcher: urlMatcher,
                                                 emailManager: emailManager,
                                                 tld: Application.appDelegate.tld,
                                                 urlSort: urlSort)

        model.credentials = makeCredentials(id: "1")
        model.save()
        XCTAssertEqual(savedCredentials?.account.id, "1")
        XCTAssertNil(deletedCredentials)

    }

    func testWhenCredentialsAreDeletedThenDeleteIsRequested() {
        let model = PasswordManagementLoginModel(onSaveRequested: onSaveRequested,
                                                onDeleteRequested: onDeleteRequested,
                                                 urlMatcher: urlMatcher,
                                                 emailManager: emailManager,
                                                 tld: Application.appDelegate.tld,
                                                 urlSort: urlSort)

        model.credentials = makeCredentials(id: "1")
        model.requestDelete()
        XCTAssertEqual(deletedCredentials?.account.id, "1")
        XCTAssertNil(savedCredentials)

    }

    func testWhenCredentialsHasNoIdThenModelStateIsNew() {
        let model = PasswordManagementLoginModel(onSaveRequested: onSaveRequested,
                                                onDeleteRequested: onDeleteRequested,
                                                 urlMatcher: urlMatcher,
                                                 emailManager: emailManager,
                                                 tld: Application.appDelegate.tld,
                                                 urlSort: urlSort)

        model.createNew()

        XCTAssertEqual(model.domain, "")
        XCTAssertEqual(model.username, "")
        XCTAssertTrue(model.isEditing)
        XCTAssertTrue(model.isNew)
    }

    func testWhenModelIsEditedThenStateIsUpdated() {
        let model = PasswordManagementLoginModel(onSaveRequested: onSaveRequested,
                                                onDeleteRequested: onDeleteRequested,
                                                 urlMatcher: urlMatcher,
                                                 emailManager: emailManager,
                                                 tld: Application.appDelegate.tld,
                                                 urlSort: urlSort)

        model.credentials = makeCredentials(id: "1")
        XCTAssertEqual(model.domain, "domain")
        XCTAssertEqual(model.username, "username")
        XCTAssertFalse(model.isEditing)
        XCTAssertFalse(model.isNew)

        model.cancel()
        XCTAssertEqual(model.domain, "domain")

        model.title = "change"
        model.cancel()

        model.username = "change"
        model.cancel()

        model.password = "change"
        model.cancel()

    }

    func onDirtyChanged(isDirty: Bool) {
        self.isDirty = isDirty
    }

    func onSaveRequested(credentials: SecureVaultModels.WebsiteCredentials) {
        savedCredentials = credentials
    }

    func onDeleteRequested(credentials: SecureVaultModels.WebsiteCredentials) {
        deletedCredentials = credentials
    }

    func makeCredentials(id: String,
                         username: String = "username",
                         domain: String = "domain",
                         password: String = "password") -> SecureVaultModels.WebsiteCredentials {

        let account = SecureVaultModels.WebsiteAccount(id: id, username: username, domain: domain)
        return SecureVaultModels.WebsiteCredentials(account: account, password: password.data(using: .utf8)!)
    }

}

extension SecureVaultModels.WebsiteAccount {

    init(id: String, title: String? = nil, username: String = "username", domain: String = "domain") {
        self.init(title: title, username: username, domain: domain)
        self.id = id
    }

}

@MainActor
final class PasswordManagementClipboardTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var notifications: NotificationCenter!
    private var workspaceNotifications: NotificationCenter!
    private var scheduledClears: [() -> Void] = []
    private var scheduledIntervals: [TimeInterval] = []

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        notifications = NotificationCenter()
        workspaceNotifications = NotificationCenter()
    }

    override func tearDown() {
        scheduledClears.forEach { $0() }
        scheduledClears.removeAll()
        scheduledIntervals.removeAll()
        pasteboard.releaseGlobally()
        pasteboard = nil
        notifications = nil
        workspaceNotifications = nil
        super.tearDown()
    }

    func testPasswordIsClearedAtScheduledDeadline() {
        let model = makeModel()
        model.copy("test-password", fieldType: .password)

        XCTAssertEqual(pasteboard.string(forType: .string), "test-password")
        XCTAssertEqual(scheduledIntervals, [60])
        scheduledClears.first?()
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testExpirationPreservesNewerClipboardContentsEvenWhenTextMatches() {
        let model = makeModel()
        model.copy("test-password", fieldType: .password)
        pasteboard.copy("test-password")

        scheduledClears.first?()

        XCTAssertEqual(pasteboard.string(forType: .string), "test-password")
    }

    func testCopyingAnotherPasswordStartsANewExpiration() {
        let model = makeModel()
        model.copy("first-password", fieldType: .password)
        model.copy("second-password", fieldType: .password)
        XCTAssertEqual(scheduledClears.count, 2)

        scheduledClears.first?()
        XCTAssertEqual(pasteboard.string(forType: .string), "second-password")
        scheduledClears.last?()
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testExpirationStillRunsAfterModelIsReleased() {
        var model: PasswordManagementLoginModel? = makeModel()
        let isModelReleased = { [weak model] in model == nil }
        model?.copy("test-password", fieldType: .password)
        model = nil

        XCTAssertTrue(isModelReleased())
        scheduledClears.first?()
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testOtherFieldsDoNotScheduleExpiration() {
        let model = makeModel()
        model.copy("test-user", fieldType: .username)
        XCTAssertEqual(pasteboard.string(forType: .string), "test-user")
        model.copy("test-note")

        XCTAssertEqual(pasteboard.string(forType: .string), "test-note")
        XCTAssertTrue(scheduledClears.isEmpty)
    }

    func testQuitClearsPassword() {
        let model = makeModel()
        model.copy("test-password", fieldType: .password)

        notifications.post(name: NSApplication.willTerminateNotification, object: nil)

        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testSleepClearsPassword() {
        let model = makeModel()
        model.copy("test-password", fieldType: .password)

        workspaceNotifications.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testQuitAndSleepPreserveNewerClipboardContents() {
        let model = makeModel()
        model.copy("test-password", fieldType: .password)
        pasteboard.copy("newer-text")

        notifications.post(name: NSApplication.willTerminateNotification, object: nil)
        workspaceNotifications.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "newer-text")
    }

    private func makeModel() -> PasswordManagementLoginModel {
        PasswordManagementLoginModel(
            onSaveRequested: { _ in },
            onDeleteRequested: { _ in },
            urlMatcher: AutofillDomainNameUrlMatcher(),
            emailManager: EmailManager(),
            tld: TLD(),
            urlSort: AutofillDomainNameUrlSort(),
            pasteboard: pasteboard,
            notificationCenter: notifications,
            workspaceNotificationCenter: workspaceNotifications,
            scheduleClipboardClear: { [weak self] interval, clear in
                self?.scheduledIntervals.append(interval)
                self?.scheduledClears.append(clear)
            })
    }
}
