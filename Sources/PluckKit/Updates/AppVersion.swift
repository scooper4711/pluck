import Foundation

/// A version such as `0.10.2`, compared number by number. A leading `v` and any suffix after the
/// numbers (`-rc.1`) are ignored, and missing numbers count as zero, so `1.0` equals `v1.0.0`.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let numbers: [Int]

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "v" || $0 == "V" })
        let numeric = trimmed.prefix(while: { $0.isNumber || $0 == "." })
        numbers = numeric.split(separator: ".").compactMap { Int($0) }
    }

    public var description: String {
        numbers.isEmpty ? "0" : numbers.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs).lexicographicallyPrecedes(rhs.padded(to: lhs))
    }

    private func padded(to other: AppVersion) -> [Int] {
        numbers + Array(repeating: 0, count: max(0, other.numbers.count - numbers.count))
    }
}
