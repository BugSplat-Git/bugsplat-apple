import Foundation

/// One line of `Thread.callStackSymbols` / `NSException.callStackSymbols`:
/// `"3   MyApp   0x0000000104a1c2f0 $s5MyApp9ViewModelC4loadyyF + 212"`.
struct CallStackFrame: Equatable {
    var index: Int
    var module: String
    var address: UInt64
    var symbol: String
    var offset: Int
}

enum CallStackSymbols {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s+(\S+)\s+(0x[0-9A-Fa-f]+)\s+(.*?)(?:\s\+\s(\d+))?\s*$"#)

    static func parse(_ lines: [String]) -> [CallStackFrame] {
        lines.compactMap(parse)
    }

    static func parse(_ line: String) -> CallStackFrame? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = pattern.firstMatch(in: line, range: range) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: line) else { return nil }
            return String(line[swiftRange])
        }
        guard let index = group(1).flatMap({ Int($0) }),
              let module = group(2),
              let address = group(3).flatMap({ UInt64($0.dropFirst(2), radix: 16) }) else { return nil }
        let symbol = group(4) ?? ""
        return CallStackFrame(index: index, module: module, address: address,
                              symbol: symbol.isEmpty ? String(format: "0x%llx", address) : symbol,
                              offset: group(5).flatMap { Int($0) } ?? 0)
    }
}
