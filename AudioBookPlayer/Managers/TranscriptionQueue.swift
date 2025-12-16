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
    
    nonisolated private init() {
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
            print("📋 [TranscriptionQueue] Enqueued task: bookID=\(task.bookID.uuidString), startTime=\(task.startTime)s, priority=\(task.priority)")
        } else {
            print("📋 [TranscriptionQueue] Task already exists, skipping: bookID=\(task.bookID.uuidString), startTime=\(task.startTime)s")
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
            return
        }
        
        // Get next task from queue
        guard let nextTask = queuedTasks.first else {
            return
        }
        
        // Remove from queue
        queuedTasks.removeFirst()
        
        // Check if we need to cancel oldest task to make room
        if runningTasks.count >= maxConcurrentTasks {
            // Find oldest running task
            if let oldestTask = runningTasks.values.min(by: { $0.createdAt < $1.createdAt }) {
                print("📋 [TranscriptionQueue] Max tasks reached, cancelling oldest: \(oldestTask.id.uuidString)")
                runningTasks.removeValue(forKey: oldestTask.id)
                // Note: Actual cancellation of transcription would need to be handled by TranscriptionManager
            }
        }
        
        // Add to running tasks
        runningTasks[nextTask.id] = nextTask
        
        print("📋 [TranscriptionQueue] Starting task: \(nextTask.id.uuidString), bookID=\(nextTask.bookID.uuidString), startTime=\(nextTask.startTime)s")
        
        // Execute transcription task
        Task {
            await executeTask(nextTask)
            // Remove from running tasks when done
            await removeRunningTask(nextTask.id)
        }
    }
    
    private func executeTask(_ task: TranscriptionTask) async {
        // Fetch book from PersistenceManager
        let books = PersistenceManager.shared.loadBooks()
        guard let book = books.first(where: { $0.id == task.bookID }) else {
            print("📋 [TranscriptionQueue] Book not found for task \(task.id.uuidString)")
            return
        }
        
        print("📋 [TranscriptionQueue] Executing task \(task.id.uuidString) for book '\\(book.title)' at \(task.startTime)s")
        
        // Call transcribeChunk with the specific start time
        await TranscriptionManager.shared.transcribeChunk(book: book, startTime: task.startTime)
    }
    
    private func removeRunningTask(_ taskID: UUID) async {
        runningTasks.removeValue(forKey: taskID)
        print("📋 [TranscriptionQueue] Completed task: \(taskID.uuidString)")
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
        guard await TranscriptionManager.shared.isTranscriptionAvailable() else {
            print("📋 [TranscriptionQueue] Transcription not available, skipping gap detection")
            return
        }
        
        guard await shouldProcess() else {
            print("📋 [TranscriptionQueue] Low battery, deferring gap detection")
            return
        }
        
        let database = TranscriptionDatabase.shared
        let chunkSize: TimeInterval = 120.0 // 2 minutes
        
        for book in books {
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
                
                if progress < currentPosition + threshold {
                    // Queue chunk at progress position
                    let priority: Priority = book.id == currentBookID ? .high : .medium
                    let task = TranscriptionTask(
                        bookID: book.id,
                        startTime: progress,
                        priority: priority
                    )
                    enqueue(task)
                }
            }
        }
        
        print("📋 [TranscriptionQueue] Gap detection complete, \(queuedTasks.count) tasks queued")
    }
}
