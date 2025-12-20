import Foundation

@available(iOS 26.0, *)
class TranscriptionInstanceTracker: ObservableObject {
    static let shared = TranscriptionInstanceTracker()
    
    enum InstanceStatus {
        case running
        case completed
        case failed
        case cancelled
    }
    
    struct TranscriptionInstance: Identifiable {
        let id: UUID
        let bookTitle: String // Book title
        let chapterTitle: String // Chapter title (e.g., "Chapter 1", "Chapter 14")
        let startTime: TimeInterval // Audio time range start (e.g., 120.0 for 2:00)
        let endTime: TimeInterval // Audio time range end (e.g., 240.0 for 4:00)
        let startedAt: Date // When transcription started
        var endedAt: Date? // When transcription ended
        var status: InstanceStatus
        var sentenceCount: Int
        var errorMessage: String?
        
        var duration: TimeInterval? {
            guard let endedAt = endedAt else { return nil }
            return endedAt.timeIntervalSince(startedAt)
        }
        
        var isRunning: Bool {
            status == .running
        }
        
        var timeRangeFormatted: String {
            let startHours = Int(startTime) / 3600
            let startMinutes = Int(startTime) / 60 % 60
            let startSeconds = Int(startTime) % 60
            let startFormatted = String(format: "%02d:%02d:%02d", startHours, startMinutes, startSeconds)
            
            let endHours = Int(endTime) / 3600
            let endMinutes = Int(endTime) / 60 % 60
            let endSeconds = Int(endTime) % 60
            let endFormatted = String(format: "%02d:%02d:%02d", endHours, endMinutes, endSeconds)
            
            return "\(startFormatted) - \(endFormatted)"
        }
    }
    
    @Published private(set) var instances: [TranscriptionInstance] = []
    @Published private(set) var updateTrigger: Int = 0 // Force UI updates
    
    private init() {}
    
    // MARK: - Instance Management
    
    func startInstance(bookTitle: String, chapterTitle: String, startTime: TimeInterval, endTime: TimeInterval) -> UUID {
        let instance = TranscriptionInstance(
            id: UUID(),
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            startTime: startTime,
            endTime: endTime,
            startedAt: Date(),
            endedAt: nil,
            status: .running,
            sentenceCount: 0,
            errorMessage: nil
        )
        
        // Update on main thread to ensure @Published triggers
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.instances.append(instance)
            self.updateTrigger += 1
        }
        
        let message = "📊 [TranscriptionTracker] Started instance \(instance.id.uuidString) for range \(instance.timeRangeFormatted)"
        print(message)
        FileLogger.shared.log(message, category: "TranscriptionTracker")
        return instance.id
    }
    
    func completeInstance(id: UUID, sentenceCount: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.instances.firstIndex(where: { $0.id == id }) {
                self.instances[index].endedAt = Date()
                self.instances[index].status = .completed
                self.instances[index].sentenceCount = sentenceCount
                self.updateTrigger += 1
                
                let duration = self.instances[index].duration ?? 0
                let message = "📊 [TranscriptionTracker] Completed instance \(id.uuidString) - \(sentenceCount) sentences, duration: \(String(format: "%.2f", duration))s"
                print(message)
                FileLogger.shared.log(message, category: "TranscriptionTracker")
            }
        }
    }
    
    func failInstance(id: UUID, error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.instances.firstIndex(where: { $0.id == id }) {
                self.instances[index].endedAt = Date()
                self.instances[index].status = .failed
                self.instances[index].errorMessage = error.localizedDescription
                self.updateTrigger += 1
                
                let message = "📊 [TranscriptionTracker] Failed instance \(id.uuidString) - \(error.localizedDescription)"
                print(message)
                FileLogger.shared.log(message, category: "TranscriptionTracker")
            }
        }
    }
    
    func cancelInstance(id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.instances.firstIndex(where: { $0.id == id }) {
                self.instances[index].endedAt = Date()
                self.instances[index].status = .cancelled
                self.updateTrigger += 1
                
                let message = "📊 [TranscriptionTracker] Cancelled instance \(id.uuidString)"
                print(message)
                FileLogger.shared.log(message, category: "TranscriptionTracker")
            }
        }
    }
    
    // MARK: - Statistics
    
    var runningInstances: [TranscriptionInstance] {
        instances.filter { $0.isRunning }
    }
    
    var completedInstances: [TranscriptionInstance] {
        instances.filter { $0.status == .completed }
    }
    
    var failedInstances: [TranscriptionInstance] {
        instances.filter { $0.status == .failed }
    }
    
    var totalRunningCount: Int {
        runningInstances.count
    }
    
    var averageDuration: TimeInterval {
        let completed = completedInstances.compactMap { $0.duration }
        guard !completed.isEmpty else { return 0 }
        return completed.reduce(0, +) / Double(completed.count)
    }
    
    var estimatedBatteryImpact: String {
        // Rough estimate: each 2-minute transcription takes ~30-60 seconds of CPU-intensive work
        // Running multiple instances concurrently increases battery drain
        let running = totalRunningCount
        if running == 0 {
            return "None (no active transcriptions)"
        } else if running == 1 {
            return "Low (1 active transcription)"
        } else if running <= 3 {
            return "Moderate (\(running) active transcriptions)"
        } else {
            return "High (\(running) active transcriptions - consider reducing concurrent tasks)"
        }
    }
    
}

