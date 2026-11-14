import Foundation
import KeyFinderEngine

/// Typed, validating access to a tool call's `arguments` object.
struct Arguments {
    private let value: JSONValue

    init(_ value: JSONValue) {
        self.value = value
    }

    func string(_ key: String) throws -> String {
        guard let result = try optionalString(key) else { throw ToolError.invalidArgument("Missing required argument: \(key).") }
        return result
    }

    func optionalString(_ key: String) throws -> String? {
        switch value[key] {
        case nil, .null?: return nil
        case .string(let text)?: return text.isEmpty ? nil : text
        default: throw ToolError.invalidArgument("\(key) must be a string.")
        }
    }

    func double(_ key: String) throws -> Double {
        guard let result = try optionalDouble(key) else { throw ToolError.invalidArgument("Missing required argument: \(key).") }
        return result
    }

    func optionalDouble(_ key: String) throws -> Double? {
        switch value[key] {
        case nil, .null?: return nil
        case .number(let number)? where number.isFinite: return number
        // Models sometimes send numbers as strings ("124").
        case .string(let text)?:
            guard let number = Double(text), number.isFinite else { throw ToolError.invalidArgument("\(key) must be a number.") }
            return number
        default: throw ToolError.invalidArgument("\(key) must be a number.")
        }
    }

    func optionalBool(_ key: String) throws -> Bool? {
        switch value[key] {
        case nil, .null?: return nil
        case .bool(let flag)?: return flag
        default: throw ToolError.invalidArgument("\(key) must be true or false.")
        }
    }

    func boundedInt(_ key: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let number = try optionalDouble(key) else { return fallback }
        guard number.rounded() == number, range.contains(Int(number)) else {
            throw ToolError.invalidArgument("\(key) must be a whole number from \(range.lowerBound) to \(range.upperBound).")
        }
        return Int(number)
    }

    static func camelot(_ text: String) throws -> CamelotKey {
        guard let key = CamelotKey(text) else {
            throw ToolError.invalidArgument("\(text) is not Camelot notation; use 1A-12A (minor) or 1B-12B (major), e.g. 8A.")
        }
        return key
    }

    static func positiveBPM(_ bpm: Double) throws -> Double {
        guard (20...400).contains(bpm) else { throw ToolError.invalidArgument("BPM must be between 20 and 400.") }
        return bpm
    }
}
