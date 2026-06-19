//
//  VCardFileReaderTests.swift
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

import Contacts
import Foundation
import Testing
@testable import DuckDuckGo

@Suite("VCardFileReader")
struct VCardFileReaderTests {

    @available(iOS 16, *)
    @Test("Returns parseFailure when the file can't be read", .timeLimit(.minutes(1)))
    func returnsParseFailureForUnreadableFile() {
        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".vcf")
        #expect(VCardFileReader.read(at: nonExistentURL) == nil)
    }

    @available(iOS 16, *)
    @Test("Returns parseFailure for malformed content", .timeLimit(.minutes(1)))
    func returnsParseFailureForMalformedContent() throws {
        let url = try writeVCardFile("not even close to a vCard file")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url) == nil)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a full one-contact file", .timeLimit(.minutes(1)))
    func returnsSingleContactForFullContact() throws {
        let url = try writeVCardFile(Fixtures.fullContact)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let result = VCardFileReader.read(at: url), !result.wasTruncated else {
            Issue.record("Expected a single presentable contact")
            return
        }
        let contact = result.contact
        #expect(contact.givenName == "John")
        #expect(contact.familyName == "Doe")
        #expect(!contact.phoneNumbers.isEmpty)
        #expect(!contact.emailAddresses.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a name-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForNameOnly() throws {
        let url = try writeVCardFile(Fixtures.nameOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a contact with only a phone number (no name)", .timeLimit(.minutes(1)))
    func returnsSingleContactForPhoneOnly() throws {
        let url = try writeVCardFile(Fixtures.phoneOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        // A field-less name is fine as long as the contact has a usable contact method.
        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns parseFailure for a contact with no presentable fields", .timeLimit(.minutes(1)))
    func returnsParseFailureForUnpresentableContact() throws {
        let url = try writeVCardFile(Fixtures.unpresentable)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url) == nil)
    }

    @available(iOS 16, *)
    @Test("Returns multipleContacts carrying the first contact for a multi-contact file", .timeLimit(.minutes(1)))
    func returnsMultipleContactsForMultiContact() throws {
        let url = try writeVCardFile(Fixtures.multipleContacts)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let result = VCardFileReader.read(at: url), result.wasTruncated else {
            Issue.record("Expected multiple presentable contacts")
            return
        }
        let contact = result.contact
        // We present the first contact (N:One;Person / FN:Person One) and ignore the rest.
        #expect(contact.givenName == "Person")
        #expect(contact.familyName == "One")
    }

    @available(iOS 16, *)
    @Test("Returns singleContact carrying the only presentable contact when an earlier entry is field-less", .timeLimit(.minutes(1)))
    func returnsSingleContactSkippingUnpresentableFirstEntry() throws {
        let url = try writeVCardFile(Fixtures.unpresentableThenPresentable)
        defer { try? FileManager.default.removeItem(at: url) }

        // The first card has only a job title (which isPresentable doesn't accept), so we skip it. Only
        // Vera is presentable, so this is a singleContact — multiplicity is keyed off the presentable
        // count, not the raw parsed count, and nothing presentable was dropped.
        guard let result = VCardFileReader.read(at: url), !result.wasTruncated else {
            Issue.record("Expected a single presentable contact")
            return
        }
        let contact = result.contact
        #expect(contact.givenName == "Vera")
        #expect(contact.familyName == "Visible")
    }

    @available(iOS 16, *)
    @Test("Returns singleContact (not multiple) for one real contact followed by a field-less stub", .timeLimit(.minutes(1)))
    func returnsSingleContactForRealContactFollowedByStub() throws {
        let url = try writeVCardFile(Fixtures.presentableThenUnpresentable)
        defer { try? FileManager.default.removeItem(at: url) }

        // Regression guard: a trailing empty/stub VCARD (common in real-world exports) must NOT make a
        // single real contact look like a multi-contact file — otherwise the truncated pixel over-fires
        // even though nothing presentable was dropped.
        guard let result = VCardFileReader.read(at: url), !result.wasTruncated else {
            Issue.record("Expected a single presentable contact")
            return
        }
        let contact = result.contact
        #expect(contact.givenName == "John")
        #expect(contact.familyName == "Doe")
    }

    @available(iOS 16, *)
    @Test("Returns multipleContacts carrying the first presentable contact when two presentable entries follow a field-less one", .timeLimit(.minutes(1)))
    func returnsMultipleContactsSkippingUnpresentableFirstEntry() throws {
        let url = try writeVCardFile(Fixtures.unpresentableThenTwoPresentable)
        defer { try? FileManager.default.removeItem(at: url) }

        // Two presentable contacts (after a field-less stub) ⇒ we really do drop one, so this is
        // multipleContacts carrying the first presentable contact.
        guard let result = VCardFileReader.read(at: url), result.wasTruncated else {
            Issue.record("Expected multiple presentable contacts")
            return
        }
        let contact = result.contact
        #expect(contact.givenName == "Vera")
        #expect(contact.familyName == "Visible")
    }

    @available(iOS 16, *)
    @Test("Returns parseFailure for a multi-contact file with no presentable entry", .timeLimit(.minutes(1)))
    func returnsParseFailureForMultiContactWithNoPresentableEntry() throws {
        let url = try writeVCardFile(Fixtures.multipleUnpresentable)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url) == nil)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a non-Latin name", .timeLimit(.minutes(1)))
    func returnsSingleContactForNonLatinName() throws {
        let url = try writeVCardFile(Fixtures.nonLatinName)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a contact with an embedded photo", .timeLimit(.minutes(1)))
    func returnsSingleContactForContactWithPhoto() throws {
        let url = try writeVCardFile(Fixtures.withPhoto)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    // Single-displayable-field cases: each of the six fixtures below has exactly one populated
    // property and nothing the name/org/phone/email/postal check accepts; these guard that the reader
    // returns a contact (not nil) for them.

    @available(iOS 16, *)
    @Test("Returns singleContact for a url-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForUrlOnly() throws {
        let url = try writeVCardFile(Fixtures.urlOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a birthday-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForBirthdayOnly() throws {
        let url = try writeVCardFile(Fixtures.birthdayOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a social-profile-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForSocialProfileOnly() throws {
        let url = try writeVCardFile(Fixtures.socialProfileOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for an instant-message-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForInstantMessageOnly() throws {
        let url = try writeVCardFile(Fixtures.instantMessageOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a note-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForNoteOnly() throws {
        let url = try writeVCardFile(Fixtures.noteOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    @available(iOS 16, *)
    @Test("Returns singleContact for a photo-only contact", .timeLimit(.minutes(1)))
    func returnsSingleContactForPhotoOnly() throws {
        let url = try writeVCardFile(Fixtures.photoOnly)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VCardFileReader.read(at: url)?.wasTruncated == false)
    }

    // MARK: - Helpers

    private func writeVCardFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".vcf")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private enum Fixtures {
        static let fullContact = """
        BEGIN:VCARD
        VERSION:3.0
        N:Doe;John;;;
        FN:John Doe
        ORG:Example Inc.
        TITLE:Engineer
        TEL;TYPE=CELL:+15555551234
        EMAIL:john@example.com
        ADR;TYPE=HOME:;;123 Main St;Springfield;IL;62704;USA
        URL:https://example.com
        END:VCARD
        """

        static let nameOnly = """
        BEGIN:VCARD
        VERSION:3.0
        N:Roe;Jane;;;
        FN:Jane Roe
        END:VCARD
        """

        static let phoneOnly = """
        BEGIN:VCARD
        VERSION:3.0
        FN:
        TEL;TYPE=CELL:+15555550000
        END:VCARD
        """

        static let unpresentable = """
        BEGIN:VCARD
        VERSION:3.0
        FN:
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

        // First card carries only a job title — a parseable field (so the serializer still emits a
        // contact for it) that isPresentable deliberately doesn't accept — followed by one presentable
        // contact (Vera). Only Vera is presentable, so the reader skips the stub and returns a
        // singleContact (nothing presentable was dropped).
        static let unpresentableThenPresentable = """
        BEGIN:VCARD
        VERSION:3.0
        FN:
        TITLE:Field Agent
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:Visible;Vera;;;
        FN:Vera Visible
        END:VCARD
        """

        // A field-less stub followed by TWO presentable contacts: the stub is skipped and one
        // presentable contact is genuinely dropped, so this is multipleContacts carrying Vera (the
        // first presentable one).
        static let unpresentableThenTwoPresentable = """
        BEGIN:VCARD
        VERSION:3.0
        FN:
        TITLE:Field Agent
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:Visible;Vera;;;
        FN:Vera Visible
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:Watcher;Walter;;;
        FN:Walter Watcher
        END:VCARD
        """

        // One real contact followed by a field-less stub (parseable but not presentable). Only John is
        // presentable, so the reader returns singleContact and does NOT fire the truncated pixel.
        static let presentableThenUnpresentable = """
        BEGIN:VCARD
        VERSION:3.0
        N:Doe;John;;;
        FN:John Doe
        TEL;TYPE=CELL:+15555551234
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        FN:
        TITLE:Field Agent
        END:VCARD
        """

        // Two cards whose only field is a job title (parseable but not presentable) ⇒ no contact to
        // show ⇒ parse failure.
        static let multipleUnpresentable = """
        BEGIN:VCARD
        VERSION:3.0
        FN:
        TITLE:Field Agent
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        FN:
        TITLE:Quartermaster
        END:VCARD
        """

        static let nonLatinName = """
        BEGIN:VCARD
        VERSION:3.0
        N:山田;太郎;;;
        FN:山田 太郎
        END:VCARD
        """

        // 1x1 transparent PNG, base64-encoded.
        static let withPhoto = """
        BEGIN:VCARD
        VERSION:3.0
        N:Pixel;Pat;;;
        FN:Pat Pixel
        PHOTO;ENCODING=b;TYPE=PNG:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/QqfAAAAAElFTkSuQmCC
        END:VCARD
        """

        // Single-field cases: each has exactly one populated property; these assert the reader no
        // longer mis-classifies them as parse failures.

        static let urlOnly = """
        BEGIN:VCARD
        VERSION:3.0
        URL:https://example.com
        END:VCARD
        """

        static let birthdayOnly = """
        BEGIN:VCARD
        VERSION:3.0
        BDAY:1990-06-15
        END:VCARD
        """

        static let socialProfileOnly = """
        BEGIN:VCARD
        VERSION:3.0
        X-SOCIALPROFILE;TYPE=twitter:https://twitter.com/example
        END:VCARD
        """

        static let instantMessageOnly = """
        BEGIN:VCARD
        VERSION:3.0
        IMPP;X-SERVICE-TYPE=Skype:skype:example.user
        END:VCARD
        """

        static let noteOnly = """
        BEGIN:VCARD
        VERSION:3.0
        NOTE:This contact has only a note and nothing else.
        END:VCARD
        """

        // 1x1 transparent PNG, base64-encoded (same bytes as the verified photo-only.vcf).
        static let photoOnly = """
        BEGIN:VCARD
        VERSION:3.0
        PHOTO;ENCODING=b;TYPE=PNG:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFBQIAhPbWjQAAAABJRU5ErkJggg==
        END:VCARD
        """
    }
}
