//
//  CompleteDownloadRowViewModelTests.swift
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

import BrowserServicesKit
import Contacts
import Core
import Foundation
import Testing
@testable import DuckDuckGo

@Suite("CompleteDownloadRowViewModel", .serialized)
final class CompleteDownloadRowViewModelTests {

    init() {
        PixelFiringMock.tearDown()
    }

    deinit {
        PixelFiringMock.tearDown()
    }

    @available(iOS 17, *)
    @Test("Returns a prepared event for a single-VEVENT .ics file", .timeLimit(.minutes(1)))
    func preparesEventForSingleVEvent() throws {
        let url = try writeTempFile(name: "single.ics", contents: Fixtures.singleEvent)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url)
        let prepared = viewModel.preparePreviewEvent()

        #expect(prepared != nil)
        #expect(prepared?.event.title == "Single Event")
    }

    @available(iOS 17, *)
    @Test("Returns nil for a non-.ics file", .timeLimit(.minutes(1)))
    func returnsNilForNonICSExtension() throws {
        let url = try writeTempFile(name: "calendar.txt", contents: Fixtures.singleEvent)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url)
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    @available(iOS 17, *)
    @Test("Returns nil for a multi-VEVENT file", .timeLimit(.minutes(1)))
    func returnsNilForMultipleEvents() throws {
        let url = try writeTempFile(name: "multi.ics", contents: Fixtures.multipleEvents)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url)
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    @available(iOS 17, *)
    @Test("Returns nil for malformed .ics content", .timeLimit(.minutes(1)))
    func returnsNilForMalformedContent() throws {
        let url = try writeTempFile(name: "broken.ics", contents: "not a calendar")
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url)
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    // MARK: - preparePreviewContact (.vcf)

    @available(iOS 16, *)
    @Test("Returns the contact for a single-contact .vcf", .timeLimit(.minutes(1)))
    func preparesContactForSingleVCard() throws {
        let url = try writeTempFile(name: "single.vcf", contents: Fixtures.singleContact)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url)
        let contact = viewModel.preparePreviewContact()

        #expect(contact?.givenName == "John")
        #expect(contact?.familyName == "Doe")
    }

    @available(iOS 16, *)
    @Test("Returns the first contact for a multi-contact .vcf", .timeLimit(.minutes(1)))
    func preparesFirstContactForMultiVCard() throws {
        let url = try writeTempFile(name: "multi.vcf", contents: Fixtures.multipleContacts)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url,
                                                     pixelFiring: PixelFiringMock.self)
        let contact = viewModel.preparePreviewContact()

        // We present the first contact and ignore the rest.
        #expect(contact?.givenName == "Person")
        #expect(contact?.familyName == "One")
    }

    @available(iOS 16, *)
    @Test("Returns nil for a malformed .vcf", .timeLimit(.minutes(1)))
    func returnsNilForMalformedVCard() throws {
        let url = try writeTempFile(name: "broken.vcf", contents: "not a vCard")
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url,
                                                     pixelFiring: PixelFiringMock.self)
        #expect(viewModel.preparePreviewContact() == nil)
    }

    @available(iOS 16, *)
    @Test("Returns nil for a non-.vcf file", .timeLimit(.minutes(1)))
    func returnsNilForNonVCardExtension() throws {
        let url = try writeTempFile(name: "contact.txt", contents: Fixtures.singleContact)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url)
        #expect(viewModel.preparePreviewContact() == nil)
    }

    // MARK: - ContactCardView.Coordinator (Downloads-list editor pixels)

    @available(iOS 16, *)
    @Test("Coordinator fires the saved pixel and calls onSaved when the contact is added", .timeLimit(.minutes(1)))
    func contactCardCoordinatorReportsSave() {
        var didSave = false
        var didDismiss = false
        let coordinator = ContactCardView.Coordinator(onSaved: { didSave = true },
                                                      onDismiss: { didDismiss = true },
                                                      pixelFiring: PixelFiringMock.self)
        coordinator.complete(saved: true)

        #expect(didSave)
        #expect(didDismiss)
        #expect(PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.vcardContactEditorSaved.name })
    }

    @available(iOS 16, *)
    @Test("Coordinator fires the cancelled pixel and skips onSaved on Cancel", .timeLimit(.minutes(1)))
    func contactCardCoordinatorReportsCancel() {
        var didSave = false
        var didDismiss = false
        let coordinator = ContactCardView.Coordinator(onSaved: { didSave = true },
                                                      onDismiss: { didDismiss = true },
                                                      pixelFiring: PixelFiringMock.self)
        coordinator.cancelButtonTapped()

        #expect(!didSave)
        #expect(didDismiss)
        #expect(PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.vcardContactEditorCancelled.name })
    }

    @available(iOS 16, *)
    @Test("Coordinator completes at most once (a swipe after Cancel is a no-op)", .timeLimit(.minutes(1)))
    func contactCardCoordinatorCompletesOnce() {
        var dismissCount = 0
        let coordinator = ContactCardView.Coordinator(onSaved: {},
                                                      onDismiss: { dismissCount += 1 },
                                                      pixelFiring: PixelFiringMock.self)
        coordinator.complete(saved: false)
        coordinator.complete(saved: true) // dismantle/swipe arriving after an explicit completion

        #expect(dismissCount == 1)
    }

    // MARK: - Helpers

    private func writeTempFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private enum Fixtures {
        static let singleEvent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:single@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:Single Event
        END:VEVENT
        END:VCALENDAR
        """

        static let multipleEvents = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:a@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:First Event
        END:VEVENT
        BEGIN:VEVENT
        UID:b@example.com
        DTSTART:20260602T140000Z
        DTEND:20260602T150000Z
        SUMMARY:Second Event
        END:VEVENT
        END:VCALENDAR
        """

        static let singleContact = """
        BEGIN:VCARD
        VERSION:3.0
        N:Doe;John;;;
        FN:John Doe
        TEL;TYPE=CELL:+15555551234
        END:VCARD
        """

        static let multipleContacts = """
        BEGIN:VCARD
        VERSION:3.0
        N:One;Person;;;
        FN:Person One
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:Two;Person;;;
        FN:Person Two
        END:VCARD
        """
    }
}
