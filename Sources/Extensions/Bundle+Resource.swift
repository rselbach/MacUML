import Foundation

extension Bundle {
    /// Attempts to find a resource first in the main bundle (for packaged .app builds),
    /// and falls back to the SwiftPM module bundle (for swift run / tests).
    static func appResource(name: String, extension ext: String) -> URL? {
        return Bundle.main.url(forResource: name, withExtension: ext) ??
               Bundle.module.url(forResource: name, withExtension: ext)
    }
}
