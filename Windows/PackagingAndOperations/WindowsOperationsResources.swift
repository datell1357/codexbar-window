import Foundation

public enum WindowsOperationsResources {
    public static var userPathScript: URL? {
        Bundle.module.url(forResource: "Set-CodexBarUserPath", withExtension: "ps1")
    }
}
