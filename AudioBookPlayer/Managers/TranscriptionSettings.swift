import Foundation
import Combine

class TranscriptionSettings: ObservableObject {
    static let shared = TranscriptionSettings()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "transcriptionEnabled")
            let status = isEnabled ? "ENABLED" : "DISABLED"
            print("🔧 [TranscriptionSettings] Transcription \(status)")
            FileLogger.shared.log("🔧 [TranscriptionSettings] Transcription \(status)", category: "TranscriptionSettings")
        }
    }
    
    private init() {
        // Default to enabled, but allow user to disable
        self.isEnabled = UserDefaults.standard.object(forKey: "transcriptionEnabled") as? Bool ?? true
    }
    
    func checkIfEnabled() -> Bool {
        return isEnabled
    }
    
    @available(iOS 26.0, *)
    func cancelAllTranscriptionWork() {
        Task {
            await TranscriptionQueue.shared.cancelAll()
        }
    }
}





