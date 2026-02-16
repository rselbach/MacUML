import os

enum Logging {
    static let subsystem = "com.macuml"

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}