enum TiboResetDate {
    static func timestamp(fromISO8601 text: String) -> Int64? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes[10] == 84,
              bytes[13] == 58,
              bytes[16] == 58,
              let year = decimal(bytes, at: 0, count: 4),
              let month = decimal(bytes, at: 5, count: 2),
              let day = decimal(bytes, at: 8, count: 2),
              let hour = decimal(bytes, at: 11, count: 2),
              let minute = decimal(bytes, at: 14, count: 2),
              let second = decimal(bytes, at: 17, count: 2),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...60).contains(second) else {
            return nil
        }
        return daysFromCivil(year: year, month: month, day: day) * 86_400 +
            Int64(hour * 3_600 + minute * 60 + second)
    }

    static func gmt8Display(fromISO8601 text: String?) -> String? {
        guard let text, let timestamp = timestamp(fromISO8601: text) else {
            return nil
        }
        let localTimestamp = timestamp + 8 * 3_600
        let days = localTimestamp / 86_400
        let seconds = Int(localTimestamp % 86_400)
        let date = civilFromDays(days)
        let hour = seconds / 3_600
        let minute = seconds % 3_600 / 60
        let monthNames = [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        ]
        return "\(monthNames[date.month - 1]) \(date.day)  " +
            "\(twoDigits(hour)):\(twoDigits(minute)) GMT+8"
    }

    static func hours(from earlier: String?, to later: String?) -> Double? {
        guard let earlier,
              let later,
              let earlierTimestamp = timestamp(fromISO8601: earlier),
              let laterTimestamp = timestamp(fromISO8601: later) else {
            return nil
        }
        return Double(max(0, laterTimestamp - earlierTimestamp)) / 3_600
    }

    private static func decimal(_ bytes: [UInt8], at offset: Int, count: Int) -> Int? {
        guard offset >= 0, count > 0, offset + count <= bytes.count else { return nil }
        var value = 0
        for index in offset..<(offset + count) {
            guard bytes[index] >= 48, bytes[index] <= 57 else { return nil }
            value = value * 10 + Int(bytes[index] - 48)
        }
        return value
    }

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let adjustedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return Int64(era * 146_097 + dayOfEra - 719_468)
    }

    private static func civilFromDays(_ daysSince1970: Int64) -> (month: Int, day: Int) {
        let shiftedDays = daysSince1970 + 719_468
        let era = (shiftedDays >= 0 ? shiftedDays : shiftedDays - 146_096) / 146_097
        let dayOfEra = shiftedDays - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPosition = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPosition + 2) / 5 + 1
        let month = monthPosition + (monthPosition < 10 ? 3 : -9)
        return (Int(month), Int(day))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
