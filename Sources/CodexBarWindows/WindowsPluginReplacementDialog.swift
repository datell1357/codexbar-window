#if os(Windows)
import Foundation
import WinSDK

enum WindowsPluginReplacementDialog {
    static func confirm(owner: HWND, review: WindowsPluginReplacementReview) -> Bool {
        let localization = WindowsStatusLocalization.Snapshot()
        let template = if review.restoringBackup {
            review.previousHash == nil ? "plugin_restoreMissingBackupReview" : "plugin_restoreBackupReview"
        } else {
            review.previousHash == nil ? "plugin_reinstallReview" : "plugin_replaceReview"
        }
        let message = localization.text(template)
            .replacingOccurrences(of: "{provider}", with: review.instanceID.rawValue)
            .replacingOccurrences(of: "{previous}", with: review.previousHash ?? "")
            .replacingOccurrences(of: "{replacement}", with: review.replacementHash)
        return message.withCString(encodedAs: UTF16.self) { body in
            localization.text(review.restoringBackup ? "plugin_restoreBackupTitle" : "plugin_replaceTitle").withCString(encodedAs: UTF16.self) { title in
                MessageBoxW(owner, body, title, UINT(MB_YESNO | MB_DEFBUTTON2 | MB_ICONQUESTION) |
                    (localization.isRightToLeft ? UINT(MB_RTLREADING | MB_RIGHT) : 0)) == IDYES
            }
        }
    }
}
#endif
