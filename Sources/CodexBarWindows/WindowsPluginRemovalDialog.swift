#if os(Windows)
import Foundation
import WinSDK

enum WindowsPluginRemovalDialog {
    static func confirm(owner: HWND, review: WindowsPluginRemovalReview) -> Bool {
        let localization = WindowsStatusLocalization.Snapshot()
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localization.language)
        formatter.numberStyle = .decimal
        let count = formatter.string(from: NSNumber(value: review.cacheCount)) ?? String(review.cacheCount)
        let template = review.instanceID == nil ? "plugin_removeFailedFileReview" :
            (review.sourceFilename == nil ? "plugin_removeOrphanReview" : "plugin_removeReview")
        let message = localization.text(template)
            .replacingOccurrences(of: "{provider}", with: review.instanceID?.rawValue ?? "")
            .replacingOccurrences(of: "{file}", with: self.displayFilename(review.sourceFilename ?? ""))
            .replacingOccurrences(of: "{hash}", with: review.sourceHash ?? "")
            .replacingOccurrences(of: "{count}", with: count)
            .replacingOccurrences(of: "{history}", with: review.historyFilename.map(self.displayFilename)
                ?? localization.text("plugin_removeNoHistory"))
            .replacingOccurrences(of: "{historyBoundary}", with: review.historyBoundaryFilename.map(self.displayFilename)
                ?? localization.text("plugin_removeNoHistory"))
        return message.withCString(encodedAs: UTF16.self) { body in
            localization.text(review.instanceID == nil ? "plugin_removeFailedFileTitle" : "plugin_removeTitle").withCString(encodedAs: UTF16.self) { title in
                MessageBoxW(owner, body, title, UINT(MB_YESNO | MB_DEFBUTTON2 | MB_ICONWARNING) |
                    (localization.isRightToLeft ? UINT(MB_RTLREADING | MB_RIGHT) : 0)) == IDYES
            }
        }
    }

    private static func displayFilename(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                "u{" + String(scalar.value, radix: 16) + "}"
            default: String(scalar)
            }
        }.joined()
    }
}
#endif
