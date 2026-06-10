import OSLog

/// Production-grade logger for Lumina.
/// Use `LuminaLog` instead of `print()` for all logging.
enum LuminaLog {
    static let app = Logger(subsystem: "com.lyfae.lumina", category: "app")
    static let wallpaper = Logger(subsystem: "com.lyfae.lumina", category: "wallpaper")
    static let persistence = Logger(subsystem: "com.lyfae.lumina", category: "persistence")
    static let thumbnail = Logger(subsystem: "com.lyfae.lumina", category: "thumbnail")
    static let audio = Logger(subsystem: "com.lyfae.lumina", category: "audio")
    static let power = Logger(subsystem: "com.lyfae.lumina", category: "power")
}

// Convenience extensions so existing code can migrate easily
extension Logger {
    func debug(_ message: String) {
        #if DEBUG
        self.log(level: .debug, "\(message)")
        #endif
    }
    
    func info(_ message: String) {
        self.log(level: .info, "\(message)")
    }
    
    func warning(_ message: String) {
        self.log(level: .default, "\(message)")
    }
    
    func error(_ message: String) {
        self.log(level: .error, "\(message)")
    }
}
