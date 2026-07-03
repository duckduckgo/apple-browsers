# ICSParser

A dependency-free Swift package that parses [iCalendar (RFC 5545)](https://www.rfc-editor.org/rfc/rfc5545) `.ics` files into calendar events ready to hand to EventKit.

## What is it?

`ICSParser` extracts the practical subset of iCalendar that maps to EventKit's `EKEvent` and `EKRecurrenceRule` APIs:

- **VEVENT properties:** `SUMMARY`, `DESCRIPTION`, `LOCATION`, `URL`, `DTSTART`, `DTEND`, `DURATION`
- **Date types:** UTC (`Z` suffix), naive local time, all-day (`VALUE=DATE`), TZID-anchored with IANA + bundled CLDR Windows-to-IANA mapping
- **Recurrence (RRULE) common subset:** `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY` (with optional positional like `1MO` / `-1FR`), `BYMONTHDAY`, `BYMONTH`
- **Multi-VEVENT files:** every event is parsed and returned in document order; the caller decides how to handle more than one
- **RFC 5545 line unfolding** and text-value escape sequences

## Usage

```swift
import ICSParser

let events = try ICSParser.parse(data: icsFileData)
```

Failures surface as `ICSParser.Error` cases: `notVCalendar`, `noVEvent`, `missingRequiredField`, `malformedDate`, `malformedDuration`, `unrecognizedTimeZone`, `malformedRecurrenceRule`.

## Out of scope

- `VTODO`, `VJOURNAL`, `VFREEBUSY`, `VALARM` components
- `EXDATE` / `RDATE` / `RECURRENCE-ID`
- `ATTENDEE` / `ORGANIZER` / `CATEGORIES` / `ATTACH`
- Exotic `RRULE` patterns (`BYSETPOS`, `BYWEEKNO`, complex `BYDAY` combinations)
- `VTIMEZONE` blocks with embedded DST rules (TZID is resolved through Foundation + the bundled CLDR mapping; unrecognised TZIDs throw `unrecognizedTimeZone`)
- `webcal://` URL handling

## Dependencies

None. The package depends only on `Foundation` and `EventKit` from the system frameworks.
