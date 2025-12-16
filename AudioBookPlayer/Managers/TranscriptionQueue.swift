import Foundation
import UIKit

@available(iOS 26.0, *)
actor TranscriptionQueue {
    static let shared = TranscriptionQueue()
    
    enum Priority: Int, Comparable {
        case low = 0
        case medium = 1
        case high = 2
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    struct TranscriptionTask: Identifiable {
        let id: UUID
        let bookID: UUID
        let startTime: TimeInterval
        let priority: Priority
        let createdAt: Date
        
        init(bookID: UUID, startTime: TimeInterval, priority: Priority) {
            self.id = UUID()
            self.bookID = bookID
            self.startTime = startTime
            self.priority = priority
            self.createdAt = Date()
        }
    }
    
    private var queuedTasks: [TranscriptionTask] = []
    private var runningTasks: [UUID: TranscriptionTask] = [:]
    private let maxConcurrentTasks = 5
    private var processingTask: Task<Void, Never>?
    
    private init() {
        // Start processing - use Task.detached to avoid actor isolation issues
        Task.detached {
            await TranscriptionQueue.shared.startProcessingTask()
        }
    }
    
    private func startProcessingTask() {
        processingTask = Task {
            while !Task.isCancelled {
                await processNext()
                // Wait a bit before checking again
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    // MARK: - Queue Management
    
    func enqueue(_ task: TranscriptionTask) {
        let hours = Int(task.startTime) / 3600
        let minutes = Int(task.startTime) / 60 % 60
        let seconds = Int(task.startTime) % 60
        let startTimeFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Check if task already exists (same book and start time)
        let exists = queuedTasks.contains { existingTask in
            existingTask.bookID == task.bookID && abs(existingTask.startTime - task.startTime) < 1.0
        } || runningTasks.values.contains { existingTask in
            existingTask.bookID == task.bookID && abs(existingTask.startTime - task.startTime) < 1.0
        }
        
        if !exists {
            queuedTasks.append(task)
            // Sort by priority (high first), then by creation time
            queuedTasks.sort { task1, task2 in
                if task1.priority != task2.priority {
                    return task1.priority > task2.priority
                }
                return task1.createdAt < task2.createdAt
            }
            print("📋 [TranscriptionQueue] ENQUEUED transcription task: bookID=\(task.bookID.uuidString), startTime=\(startTimeFormatted) (\(task.startTime)s), priority=\(task.priority), taskID=\(task.id.uuidString)")
            print("📋 [TranscriptionQueue] Queue now has \(queuedTasks.count) queued tasks, \(runningTasks.count) running tasks")
        } else {
            print("⚠️ [TranscriptionQueue] Task already exists (queued or running), skipping: bookID=\(task.bookID.uuidString), startTime=\(startTimeFormatted) (\(task.startTime)s)")
        }
    }
    
    func cancel(for bookID: UUID) {
        queuedTasks.removeAll { $0.bookID == bookID }
        // Note: We don't cancel running tasks - let them finish
        print("📋 [TranscriptionQueue] Cancelled queued tasks for bookID=\(bookID.uuidString)")
    }
    
    // MARK: - Task Processing
    
    
    private func processNext() async {
        // Don't process if at max capacity
        guard runningTasks.count < maxConcurrentTasks else {
            print("⏸️ [TranscriptionQueue] Cannot process next task - at max capacity (\(runningTasks.count)/\(maxConcurrentTasks) running)")
            return
        }
        
        // Get next task from queue
        guard let nextTask = queuedTasks.first else {
            // No tasks in queue - this is normal, don't log
            return
        }
        
        // Remove from queue
        queuedTasks.removeFirst()
        
        // Check if we need to cancel oldest task to make room
        if runningTasks.count >= maxConcurrentTasks {
            // Find oldest running task
            if let oldestTask = runningTasks.values.min(by: { $0.createdAt < $1.createdAt }) {
                print("⚠️ [TranscriptionQueue] Max tasks reached, cancelling oldest: \(oldestTask.id.uuidString)")
                runningTasks.removeValue(forKey: oldestTask.id)
                // Note: Actual cancellation of transcription would need to be handled by TranscriptionManager
            }
        }
        
        // Add to running tasks
        runningTasks[nextTask.id] = nextTask
        
        let hours = Int(nextTask.startTime) / 3600
        let minutes = Int(nextTask.startTime) / 60 % 60
        let seconds = Int(nextTask.startTime) % 60
        let startTimeFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        print("▶️ [TranscriptionQueue] STARTING transcription task: taskID=\(nextTask.id.uuidString), bookID=\(nextTask.bookID.uuidString), startTime=\(startTimeFormatted) (\(nextTask.startTime)s), priority=\(nextTask.priority)")
        print("▶️ [TranscriptionQueue] Queue status: \(queuedTasks.count) queued, \(runningTasks.count) running")
        
        // Execute transcription task
        Task {
            await executeTask(nextTask)
            // Remove from running tasks when done
            await removeRunningTask(nextTask.id)
        }
    }
    
    private func executeTask(_ task: TranscriptionTask) async {
        let hours = Int(task.startTime) / 3600
        let minutes = Int(task.startTime) / 60 % 60
        let seconds = Int(task.startTime) % 60
        let startTimeFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Fetch book from PersistenceManager
        let books = PersistenceManager.shared.loadBooks()
        guard let book = books.first(where: { $0.id == task.bookID }) else {
            print("❌ [TranscriptionQueue] EXECUTION FAILED - Book not found for task \(task.id.uuidString), bookID=\(task.bookID.uuidString)")
            return
        }
        
        print("▶️ [TranscriptionQueue] EXECUTING task \(task.id.uuidString) for book '\(book.title)' at startTime=\(startTimeFormatted) (\(task.startTime)s)")
        
        // Call transcribeChunk with the specific start time
        await TranscriptionManager.shared.transcribeChunk(book: book, startTime: task.startTime)
        
        print("✅ [TranscriptionQueue] Task \(task.id.uuidString) execution completed")
    }
    
    private func removeRunningTask(_ taskID: UUID) async {
        runningTasks.removeValue(forKey: taskID)
        print("✅ [TranscriptionQueue] REMOVED task from running list: taskID=\(taskID.uuidString)")
        print("✅ [TranscriptionQueue] Queue status: \(queuedTasks.count) queued, \(runningTasks.count) running")
    }
    
    // MARK: - Power-Aware Processing
    
    func shouldProcess() async -> Bool {
        // Check power state - UIDevice is MainActor isolated
        return await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            
            let batteryLevel = device.batteryLevel
            let isPluggedIn = device.batteryState == .charging || device.batteryState == .full
            
            // Process if plugged in or battery > 50%
            return isPluggedIn || batteryLevel > 0.5
        }
    }
    
    // MARK: - Gap Detection
    
    func detectTranscriptionGaps(books: [Book], currentBookID: UUID?) async {
        let startTime = Date()
        print("🔍 [TranscriptionQueue] Starting gap detection for \(books.count) books, currentBookID=\(currentBookID?.uuidString ?? "nil")")
        
        // Skip battery check on startup - not critical and adds MainActor delay
        // Battery check can be done later when actually starting transcription
        
        // Check availability (now cached, so should be fast after first call)
        guard await TranscriptionManager.shared.isTranscriberAvailable() else {
            print("❌ [TranscriptionQueue] Transcription not available, skipping gap detection")
            return
        }
        
        let database = TranscriptionDatabase.shared
        let chunkSize: TimeInterval = 120.0 // 2 minutes
        
        for book in books {
            let bookStartTime = Date()
            let chunkCount = await database.getChunkCount(bookID: book.id)
            
            if chunkCount == 0 {
                // No transcription - queue initial chunk
                let priority: Priority = book.id == currentBookID ? .high : .low
                let task = TranscriptionTask(
                    bookID: book.id,
                    startTime: 0.0,
                    priority: priority
                )
                enqueue(task)
            } else {
                // Check if current position needs transcription
                let progress = await database.getTranscriptionProgress(bookID: book.id)
                let currentPosition = book.currentPosition
                let threshold = chunkSize / 2.0
                
                // Removed unused formatted strings - they were for debugging
                
                // First, check if we need to fill the gap from progress to current position
                if progress < currentPosition + threshold {
                    // Queue chunk at progress position to fill the gap sequentially
                    let priority: Priority = book.id == currentBookID ? .high : .medium
                    let task = TranscriptionTask(
                        bookID: book.id,
                        startTime: progress,
                        priority: priority
                    )
                    enqueue(task)
                }
                
                // Also check if transcription is needed specifically at the current position
                // This handles the case where the user is at a position far ahead of progress
                if let chunkStartTime = await TranscriptionManager.shared.checkIfTranscriptionNeededAtSeekPosition(
                    bookID: book.id,
                    seekTime: currentPosition,
                    chunkSize: chunkSize
                ) {
                    let priority: Priority = book.id == currentBookID ? .high : .medium
                    let task = TranscriptionTask(
                        bookID: book.id,
                        startTime: chunkStartTime,
                        priority: priority
                    )
                    enqueue(task)
                }
            }
            let bookElapsed = Date().timeIntervalSince(bookStartTime)
            print("⏱️ [Performance] Gap detection for '\(book.title)' - elapsed: \(String(format: "%.3f", bookElapsed))s")
        }
        
        let totalElapsed = Date().timeIntervalSince(startTime)
        print("⏱️ [Performance] Gap detection complete - total elapsed: \(String(format: "%.3f", totalElapsed))s, \(queuedTasks.count) tasks queued")
        print("✅ [TranscriptionQueue] Gap detection complete, \(queuedTasks.count) tasks queued")
    }
}
