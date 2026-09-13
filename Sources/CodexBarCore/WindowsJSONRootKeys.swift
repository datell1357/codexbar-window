#if os(Windows)
import Foundation

/// Checks root object keys after Foundation has accepted the JSON syntax.
/// Foundation may collapse duplicate keys; credentials must not depend on which value it keeps.
enum WindowsJSONRootKeys {
    static func areUnique(in data: Data, maximumBytes: Int) -> Bool {
        guard maximumBytes > 0, data.count <= maximumBytes else { return false }
        let bytes = Array(data)
        var index = 0
        var depth = 0
        var expectsRootKey = false
        var keys = Set<String>()
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 {
                let start = index
                index += 1
                var closed = false
                while index < bytes.count {
                    if bytes[index] == 0x5C {
                        // Escape syntax was already checked by JSONSerialization. Skip its next byte
                        // so escaped quotes cannot end the string; Unicode digits contain no quotes.
                        index += 2
                    } else if bytes[index] == 0x22 {
                        index += 1
                        closed = true
                        break
                    } else { index += 1 }
                }
                guard closed, index <= bytes.count else { return false }
                if depth == 1, expectsRootKey {
                    guard let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])),
                          keys.insert(key).inserted else { return false }
                    expectsRootKey = false
                }
                continue
            }
            switch byte {
            case 0x7B, 0x5B:
                depth += 1
                if depth == 1 {
                    guard byte == 0x7B else { return false }
                    expectsRootKey = true
                }
            case 0x7D, 0x5D:
                depth -= 1
                guard depth >= 0 else { return false }
            case 0x2C:
                if depth == 1 { expectsRootKey = true }
            default: break
            }
            index += 1
        }
        return depth == 0
    }
}
#endif
