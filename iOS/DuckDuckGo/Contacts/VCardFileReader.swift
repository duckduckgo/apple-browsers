//
//  VCardFileReader.swift
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

/// Pure, side-effect-free classifier for a `.vcf` file URL.
enum VCardFileReader {

    /// The first presentable contact in the file, plus whether other presentable contacts were
    /// dropped (so the caller can fire the "truncated" pixel). `read(at:)` returns `nil` when the
    /// file can't be parsed or has no presentable contact.
    struct Result {
        let contact: CNContact
        let wasTruncated: Bool
    }

    /// Parses a `.vcf` into a `Result`, or `nil` when it can't be parsed or has no presentable contact.
    static func read(at url: URL) -> Result? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let contacts = try CNContactVCardSerialization.contacts(with: data)
            let presentableContacts = contacts.filter(isPresentable)
            guard let presentable = presentableContacts.first else { return nil }
            // Multiplicity is keyed off the count of *presentable* contacts, not the raw parsed count,
            // so a single real contact followed by a field-less stub (common in real-world exports)
            // isn't mis-reported as truncated. We carry the first presentable contact and flag
            // truncation only when we actually drop one.
            return Result(contact: presentable, wasTruncated: presentableContacts.count > 1)
        } catch {
            return nil
        }
    }

    /// A contact is presentable when it has at least one field worth showing on the unknown-contact card.
    private static func isPresentable(_ contact: CNContact) -> Bool {
        let hasName = presentableField(contact, CNContactGivenNameKey) { !$0.givenName.isEmpty }
            || presentableField(contact, CNContactFamilyNameKey) { !$0.familyName.isEmpty }
            || presentableField(contact, CNContactMiddleNameKey) { !$0.middleName.isEmpty }
            || presentableField(contact, CNContactNamePrefixKey) { !$0.namePrefix.isEmpty }
            || presentableField(contact, CNContactNameSuffixKey) { !$0.nameSuffix.isEmpty }
            || presentableField(contact, CNContactOrganizationNameKey) { !$0.organizationName.isEmpty }
        let hasContactMethod = presentableField(contact, CNContactPhoneNumbersKey) { !$0.phoneNumbers.isEmpty }
            || presentableField(contact, CNContactEmailAddressesKey) { !$0.emailAddresses.isEmpty }
            || presentableField(contact, CNContactPostalAddressesKey) { !$0.postalAddresses.isEmpty }
        let hasOtherDisplayableField = presentableField(contact, CNContactUrlAddressesKey) { !$0.urlAddresses.isEmpty }
            || presentableField(contact, CNContactBirthdayKey) { $0.birthday != nil }
            || presentableField(contact, CNContactDatesKey) { !$0.dates.isEmpty }
            || presentableField(contact, CNContactSocialProfilesKey) { !$0.socialProfiles.isEmpty }
            || presentableField(contact, CNContactInstantMessageAddressesKey) { !$0.instantMessageAddresses.isEmpty }
            || presentableField(contact, CNContactNoteKey) { !$0.note.isEmpty }
            || presentableField(contact, CNContactImageDataAvailableKey) { $0.imageDataAvailable }
        return hasName || hasContactMethod || hasOtherDisplayableField
    }

    /// Evaluates `isPopulated` only when `key` was populated by the serializer, otherwise returns
    /// false. Every `CNContact` read in this type must go through here: touching a key the serializer
    /// didn't fetch raises `CNContactPropertyNotFetchedException`.
    private static func presentableField(_ contact: CNContact,
                                         _ key: String,
                                         isPopulated: (CNContact) -> Bool) -> Bool {
        contact.isKeyAvailable(key) && isPopulated(contact)
    }
}
