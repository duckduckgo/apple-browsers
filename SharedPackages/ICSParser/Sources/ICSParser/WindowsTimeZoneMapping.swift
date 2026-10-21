//
//  WindowsTimeZoneMapping.swift
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

/// Maps Microsoft Windows / Outlook timezone names to their canonical IANA identifiers, derived
/// from the CLDR `windowsZones.xml` supplemental data.
///
/// Used as the second-chance fallback when `TimeZone(identifier:)` doesn't recognise a TZID
/// (e.g. `Eastern Standard Time` instead of `America/New_York`). Covers the major populated
/// zones; if a less common entry is missing, the parser surfaces `unrecognizedTimeZone` so the
/// integration can decide what to do.
enum WindowsTimeZoneMapping {

    static func ianaIdentifier(for windowsName: String) -> String? {
        mapping[windowsName]
    }

    private static let mapping: [String: String] = [
        // North America
        "Eastern Standard Time": "America/New_York",
        "Eastern Daylight Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Central Daylight Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "Mountain Daylight Time": "America/Denver",
        "Pacific Standard Time": "America/Los_Angeles",
        "Pacific Daylight Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage",
        "Aleutian Standard Time": "America/Adak",
        "Hawaiian Standard Time": "Pacific/Honolulu",
        "Newfoundland Standard Time": "America/St_Johns",
        "Atlantic Standard Time": "America/Halifax",
        "US Eastern Standard Time": "America/Indianapolis",
        "US Mountain Standard Time": "America/Phoenix",
        "Pacific Standard Time (Mexico)": "America/Tijuana",
        "Mountain Standard Time (Mexico)": "America/Chihuahua",
        "Central Standard Time (Mexico)": "America/Mexico_City",
        "Eastern Standard Time (Mexico)": "America/Cancun",

        // South America
        "SA Pacific Standard Time": "America/Bogota",
        "Pacific SA Standard Time": "America/Santiago",
        "SA Western Standard Time": "America/La_Paz",
        "SA Eastern Standard Time": "America/Cayenne",
        "Argentina Standard Time": "America/Buenos_Aires",
        "Paraguay Standard Time": "America/Asuncion",
        "Central Brazilian Standard Time": "America/Cuiaba",
        "E. South America Standard Time": "America/Sao_Paulo",
        "Montevideo Standard Time": "America/Montevideo",
        "Venezuela Standard Time": "America/Caracas",

        // Greenland / Atlantic
        "Greenland Standard Time": "America/Godthab",
        "Azores Standard Time": "Atlantic/Azores",
        "Cape Verde Standard Time": "Atlantic/Cape_Verde",

        // Europe / UK
        "GMT Standard Time": "Europe/London",
        "Greenwich Standard Time": "Atlantic/Reykjavik",
        "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest",
        "Romance Standard Time": "Europe/Paris",
        "Central European Standard Time": "Europe/Warsaw",
        "E. Europe Standard Time": "Europe/Chisinau",
        "FLE Standard Time": "Europe/Kiev",
        "GTB Standard Time": "Europe/Bucharest",
        "Russian Standard Time": "Europe/Moscow",
        "Belarus Standard Time": "Europe/Minsk",
        "Russia Time Zone 3": "Europe/Samara",
        "Turkey Standard Time": "Europe/Istanbul",
        "Kaliningrad Standard Time": "Europe/Kaliningrad",

        // Middle East
        "Iran Standard Time": "Asia/Tehran",
        "Arabian Standard Time": "Asia/Dubai",
        "Arab Standard Time": "Asia/Riyadh",
        "Arabic Standard Time": "Asia/Baghdad",
        "Israel Standard Time": "Asia/Jerusalem",
        "Jordan Standard Time": "Asia/Amman",
        "Middle East Standard Time": "Asia/Beirut",
        "Syria Standard Time": "Asia/Damascus",

        // Africa
        "Egypt Standard Time": "Africa/Cairo",
        "Libya Standard Time": "Africa/Tripoli",
        "Morocco Standard Time": "Africa/Casablanca",
        "Namibia Standard Time": "Africa/Windhoek",
        "South Africa Standard Time": "Africa/Johannesburg",
        "W. Central Africa Standard Time": "Africa/Lagos",
        "E. Africa Standard Time": "Africa/Nairobi",
        "Sudan Standard Time": "Africa/Khartoum",

        // Indian Ocean / South Asia
        "Mauritius Standard Time": "Indian/Mauritius",
        "Reunion Standard Time": "Indian/Reunion",
        "India Standard Time": "Asia/Kolkata",
        "Pakistan Standard Time": "Asia/Karachi",
        "Afghanistan Standard Time": "Asia/Kabul",
        "Sri Lanka Standard Time": "Asia/Colombo",
        "Bangladesh Standard Time": "Asia/Dhaka",
        "Nepal Standard Time": "Asia/Katmandu",
        "Myanmar Standard Time": "Asia/Rangoon",
        "Bhutan Standard Time": "Asia/Thimphu",

        // Central / East Asia
        "Caucasus Standard Time": "Asia/Yerevan",
        "Georgian Standard Time": "Asia/Tbilisi",
        "Azerbaijan Standard Time": "Asia/Baku",
        "Ekaterinburg Standard Time": "Asia/Yekaterinburg",
        "N. Central Asia Standard Time": "Asia/Novosibirsk",
        "North Asia Standard Time": "Asia/Krasnoyarsk",
        "North Asia East Standard Time": "Asia/Irkutsk",
        "Yakutsk Standard Time": "Asia/Yakutsk",
        "Vladivostok Standard Time": "Asia/Vladivostok",
        "Magadan Standard Time": "Asia/Magadan",
        "Sakhalin Standard Time": "Asia/Sakhalin",
        "Russia Time Zone 10": "Asia/Srednekolymsk",
        "Russia Time Zone 11": "Asia/Kamchatka",
        "SE Asia Standard Time": "Asia/Bangkok",
        "Singapore Standard Time": "Asia/Singapore",
        "Malay Peninsula Standard Time": "Asia/Kuala_Lumpur",
        "China Standard Time": "Asia/Shanghai",
        "Taipei Standard Time": "Asia/Taipei",
        "Korea Standard Time": "Asia/Seoul",
        "North Korea Standard Time": "Asia/Pyongyang",
        "Tokyo Standard Time": "Asia/Tokyo",
        "Ulaanbaatar Standard Time": "Asia/Ulaanbaatar",
        "Tomsk Standard Time": "Asia/Tomsk",
        "Astana Standard Time": "Asia/Almaty",
        "West Asia Standard Time": "Asia/Tashkent",

        // Australia / Pacific / NZ
        "AUS Eastern Standard Time": "Australia/Sydney",
        "AUS Central Standard Time": "Australia/Darwin",
        "W. Australia Standard Time": "Australia/Perth",
        "Tasmania Standard Time": "Australia/Hobart",
        "Cen. Australia Standard Time": "Australia/Adelaide",
        "E. Australia Standard Time": "Australia/Brisbane",
        "Lord Howe Standard Time": "Australia/Lord_Howe",
        "New Zealand Standard Time": "Pacific/Auckland",
        "Chatham Islands Standard Time": "Pacific/Chatham",
        "Fiji Standard Time": "Pacific/Fiji",
        "Samoa Standard Time": "Pacific/Apia",
        "Tonga Standard Time": "Pacific/Tongatapu",
        "Line Islands Standard Time": "Pacific/Kiritimati",
        "Norfolk Standard Time": "Pacific/Norfolk",
        "Easter Island Standard Time": "Pacific/Easter",

        // UTC offsets
        "UTC": "Etc/UTC",
        "UTC+12": "Etc/GMT-12",
        "UTC+13": "Etc/GMT-13",
        "UTC-02": "Etc/GMT+2",
        "UTC-08": "Etc/GMT+8",
        "UTC-09": "Etc/GMT+9",
        "UTC-11": "Etc/GMT+11"
    ]
}
