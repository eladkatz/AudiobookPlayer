import Foundation

class FileLogger {
    static let shared = FileLogger()
    
    private let logQueue = DispatchQueue(label: "com.audiobookplayer.logger", qos: .utility)
    private var logFileURL: URL?
    private let maxLogFileSize: Int64 = 10 * 1024 * 1024 // 10 MB
    
    private init() {
        setupLogFile()
    }
    
    private func setupLogFile() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ [FileLogger] Failed to get documents directory")
            return
        }
        
        let logFileName = "audiobook_player_log.txt"
        logFileURL = documentsDirectory.appendingPathComponent(logFileName)
        
        // Create initial log entry
        logToFile("=== Log file initialized at \(Date()) ===\n")
    }
    
    func log(_ message: String, category: String = "App") {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(category)] \(message)\n"
        
        // Always print to console
        print(message)
        
        // Write to file asynchronously
        logQueue.async { [weak self] in
            self?.logToFile(logMessage)
        }
    }
    
    private func logToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }
        
        do {
            // Check file size and rotate if needed
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
                if let fileSize = attributes[.size] as? Int64, fileSize > maxLogFileSize {
                    rotateLogFile()
                }
            }
            
            // Append to file
            if let fileHandle = FileHandle(forWritingAtPath: logFileURL.path) {
                fileHandle.seekToEndOfFile()
                if let data = message.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                // File doesn't exist, create it
                try message.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("❌ [FileLogger] Failed to write to log file: \(error)")
        }
    }
    
    private func rotateLogFile() {
        guard let logFileURL = logFileURL else { return }
        
        let backupURL = logFileURL.deletingLastPathComponent().appendingPathComponent("audiobook_player_log_old.txt")
        
        do {
            // Remove old backup if it exists
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            
            // Move current log to backup
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try FileManager.default.moveItem(at: logFileURL, to: backupURL)
            }
        } catch {
            print("❌ [FileLogger] Failed to rotate log file: \(error)")
        }
    }
    
    func getLogFilePath() -> String? {
        return logFileURL?.path
    }
    
    func exportLogs() -> String {
        guard let logFileURL = logFileURL,
              let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            return "No log file found or unable to read log file."
        }
        return content
    }
    
    func clearLogs() {
        logQueue.async { [weak self] in
            guard let self = self, let logFileURL = self.logFileURL else { return }
            
            do {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    try FileManager.default.removeItem(at: logFileURL)
                }
                self.logToFile("=== Log file cleared at \(Date()) ===\n")
            } catch {
                print("❌ [FileLogger] Failed to clear log file: \(error)")
            }
        }
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}




