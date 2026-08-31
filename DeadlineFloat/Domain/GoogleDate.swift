import Foundation

/// Parsing and formatting of the two date shapes the Calendar API uses.
///
/// Written by hand rather than with `ISO8601DateFormatter` for three reasons:
/// the result is `Sendable` and allocation-free to share, it accepts every
/// offset spelling Google emits (`Z`, `+05:30`, `-0400`) plus optional
/// fractional seconds, and it is deterministic under test regardless of the
/// host's locale or default time zone.
enum GoogleDate {
    /// Parses an RFC 3339 timestamp such as `2026-08-30T23:59:00-04:00`.
    ///
    /// A missing offset is treated as UTC, which matches RFC 3339's requirement
    /// that offsets be explicit; the Calendar API always supplies one.
    static func timestamp(from string: String) -> Date? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 19 else { return nil }

        let chars = Array(text)
        guard chars[4] == "-", chars[7] == "-" else { return nil }
        let separator = chars[10]
        guard separator == "T" || separator == "t" || separator == " " else { return nil }
        guard chars[13] == ":", chars[16] == ":" else { return nil }

        guard let year = Int(String(chars[0..<4])),
              let month = Int(String(chars[5..<7])),
              let day = Int(String(chars[8..<10])),
              let hour = Int(String(chars[11..<13])),
              let minute = Int(String(chars[14..<16])),
              let second = Int(String(chars[17..<19]))
        else { return nil }

        var index = 19
        var fractional: TimeInterval = 0

        if index < chars.count, chars[index] == "." || chars[index] == "," {
            index += 1
            var digits = ""
            while index < chars.count, chars[index].isNumber {
                digits.append(chars[index])
                index += 1
            }
            if !digits.isEmpty, let value = Double("0." + digits) { fractional = value }
        }

        var offsetSeconds = 0
        if index < chars.count {
            let marker = chars[index]
            if marker == "Z" || marker == "z" {
                offsetSeconds = 0
                index += 1
            } else if marker == "+" || marker == "-" {
                let sign = marker == "-" ? -1 : 1
                let rest = String(chars[(index + 1)...]).replacingOccurrences(of: ":", with: "")
                guard rest.count >= 4 else { return nil }
                let restChars = Array(rest)
                guard let offsetHours = Int(String(restChars[0..<2])),
                      let offsetMinutes = Int(String(restChars[2..<4]))
                else { return nil }
                offsetSeconds = sign * (offsetHours * 3600 + offsetMinutes * 60)
                index = chars.count
            } else {
                return nil
            }
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(secondsFromGMT: offsetSeconds) else { return nil }
        calendar.timeZone = zone
        guard let date = calendar.date(from: components) else { return nil }
        return fractional == 0 ? date : date.addingTimeInterval(fractional)
    }

    /// Parses an all-day date such as `2026-08-30` into local midnight.
    ///
    /// Google stores all-day events as floating dates. Resolving them in the
    /// display time zone is what Google Calendar's own interface does, and it is
    /// what makes "today" mean today on this Mac.
    static func allDayStart(from string: String, calendar: Calendar) -> Date? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }
        // Guards against zones where midnight does not exist on a DST boundary.
        return calendar.startOfDay(for: date)
    }

    /// Resolves either shape of `EventDateTime` to an instant.
    static func instant(from value: GoogleEventDateTime?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        if let dateTime = value.dateTime { return timestamp(from: dateTime) }
        if let date = value.date { return allDayStart(from: date, calendar: calendar) }
        return nil
    }

    /// UTC RFC 3339 rendering used for `timeMin` / `timeMax` query parameters.
    static func rfc3339String(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            c.year ?? 1970, c.month ?? 1, c.day ?? 1,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }
}
