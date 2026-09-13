#if os(Windows)
import Foundation

/// Preserve the credential input limit while sharing the root-key scanner.
enum WindowsWindsurfSessionJSONKeys {
    static func areUnique(in data: Data) -> Bool {
        WindowsJSONRootKeys.areUnique(in: data, maximumBytes: 65_536)
    }
}
#endif
