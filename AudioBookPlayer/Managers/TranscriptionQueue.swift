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
        let chapterIndex: Int  // Chapter index in the chapters array (0-based)
        let startTime: TimeInterval  // Chapter start time
        let endTime: TimeInterval    // Chapter end time
        let priority: Priority
        let createdAt: Date
        var retryCount: Int = 0
        
        init(bookID: UUID, chapterIndex: Int, startTime: TimeInterval, endTime: TimeInterval, priority: Priority, retryCount: Int = 0) {
            self.id = UUID()
            self.bookID = bookID
            self.chapterIndex = chapterIndex
            self.startTime = startTime
            self.endTime = endTime
            self.priority = priority
            self.createdAt = Date()
            self.retryCount = retryCount
        }
    }
    
    private var queuedTasks: [TranscriptionTask] = []
    private var currentTask: TranscriptionTask?
    private var nextChapterTask: TranscriptionTask? // Track next chapter for auto-start
    private var currentTaskHandle: Task<Void, Never>?
    private var progressMonitorTask: Task<Void, Never>?
    private let maxRetries = 3
    private let progressTimeout: TimeInterval = 30.0 // 30 seconds
    private let firstSentenceGracePeriod: TimeInterval = 60.0 // 60 seconds for first sentence
    private var processingTask: Task<Void, Never>?
    
    // MARK: - Debug Access
    
    func getQueuedTasks() -> [TranscriptionTask] {
        queuedTasks
    }
    
    func getRunningTasks() -> [TranscriptionTask] {
        if let current = currentTask {
            return [current]
        }
        return []
    }
    
    func getQueueStatus() -> (queued: Int, running: Int, maxConcurrent: Int) {
        (queued: queuedTasks.count, running: currentTask != nil ? 1 : 0, maxConcurrent: 1)
    }
    
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
    
    func enqueueChapter(book: Book, chapterIndex: Int, startTime: TimeInterval, endTime: TimeInterval, priority: Priority = .high) {
        // Check if transcription is enabled
        guard TranscriptionSettings.shared.isEnabled else {
            let disabledMsg = "🚫 [TranscriptionQueue] Transcription is disabled - skipping enqueue for chapter: bookID=\(book.id.uuidString), chapterIndex=\(chapterIndex)"
            print(disabledMsg)
            FileLogger.shared.log(disabledMsg, category: "TranscriptionQueue")
            return
        }
        
        // If this is the current chapter and we have a running task, cancel it (user scrubbed to new chapter)
        if let current = currentTask, current.bookID == book.id && current.chapterIndex == chapterIndex {
            // Same chapter - don't cancel, just skip
            let skipMsg = "⚠️ [TranscriptionQueue] Chapter already being transcribed, skipping: bookID=\(book.id.uuidString), chapterIndex=\(chapterIndex)"
            print(skipMsg)
            FileLogger.shared.log(skipMsg, category: "TranscriptionQueue")
            return
        }
        
        // Cancel current task if running (user scrubbed to different chapter)
        if currentTask != nil {
            let cancelMsg = "🔄 [TranscriptionQueue] Cancelling current task to start new chapter transcription"
            print(cancelMsg)
            FileLogger.shared.log(cancelMsg, category: "TranscriptionQueue")
            currentTaskHandle?.cancel()
            progressMonitorTask?.cancel()
            currentTask = nil
            currentTaskHandle = nil
            progressMonitorTask = nil
        }
        
        // Cancel next chapter task if it doesn't match the new current chapter's next
        // (User scrubbed away, so old next chapter is no longer relevant)
        if let next = nextChapterTask, next.chapterIndex != chapterIndex {
            let cancelNextMsg = "🔄 [TranscriptionQueue] Cancelling old next chapter task (user scrubbed away)"
            print(cancelNextMsg)
            FileLogger.shared.log(cancelNextMsg, category: "TranscriptionQueue")
            // Remove from queue if it's there
            queuedTasks.removeAll { $0.id == next.id }
            nextChapterTask = nil
        }
        
        // Check if task already exists in queue
        let existsInQueue = queuedTasks.contains { existingTask in
            existingTask.bookID == book.id && existingTask.chapterIndex == chapterIndex
        }
        
        if !existsInQueue {
            let task = TranscriptionTask(
                bookID: book.id,
                chapterIndex: chapterIndex,
                startTime: startTime,
                endTime: endTime,
                priority: priority
            )
            queuedTasks.append(task)
            // Sort by priority (high first), then by creation time
            queuedTasks.sort { task1, task2 in
                if task1.priority != task2.priority {
                    return task1.priority > task2.priority
                }
                return task1.createdAt < task2.createdAt
            }
            let enqueueMsg1 = "📋 [TranscriptionQueue] ENQUEUED chapter transcription: bookID=\(book.id.uuidString), chapterIndex=\(chapterIndex), priority=\(priority), taskID=\(task.id.uuidString)"
            let enqueueMsg2 = "📋 [TranscriptionQueue] Queue now has \(queuedTasks.count) queued tasks"
            print(enqueueMsg1)
            print(enqueueMsg2)
            FileLogger.shared.log(enqueueMsg1, category: "TranscriptionQueue")
            FileLogger.shared.log(enqueueMsg2, category: "TranscriptionQueue")
        } else {
            let skipMsg = "⚠️ [TranscriptionQueue] Chapter already queued, skipping: bookID=\(book.id.uuidString), chapterIndex=\(chapterIndex)"
            print(skipMsg)
            FileLogger.shared.log(skipMsg, category: "TranscriptionQueue")
        }
        
        // Start processing if not already running
        if currentTask == nil {
            Task.detached {
                await TranscriptionQueue.shared.processNext()
            }
        }
    }
    
    func cancel(for bookID: UUID) {
        queuedTasks.removeAll { $0.bookID == bookID }
        // Cancel current task if it matches
        if let current = currentTask, current.bookID == bookID {
            currentTaskHandle?.cancel()
            progressMonitorTask?.cancel()
            currentTask = nil
            currentTaskHandle = nil
            progressMonitorTask = nil
        }
        let cancelMsg = "📋 [TranscriptionQueue] Cancelled tasks for bookID=\(bookID.uuidString)"
        print(cancelMsg)
        FileLogger.shared.log(cancelMsg, category: "TranscriptionQueue")
    }
    
    func cancelAll() {
        let queuedCount = queuedTasks.count
        queuedTasks.removeAll()
        // Cancel current task
        if currentTask != nil {
            currentTaskHandle?.cancel()
            progressMonitorTask?.cancel()
            currentTask = nil
            currentTaskHandle = nil
            progressMonitorTask = nil
        }
        // Clear next chapter task
        nextChapterTask = nil
        let cancelMsg = "📋 [TranscriptionQueue] Cancelled all tasks (\(queuedCount) queued, 1 running)"
        print(cancelMsg)
        FileLogger.shared.log(cancelMsg, category: "TranscriptionQueue")
    }
    
    // MARK: - Next Chapter Management
    
    func enqueueNextChapter(book: Book, chapterIndex: Int, startTime: TimeInterval, endTime: TimeInterval) {
        // Check if transcription is enabled
        guard TranscriptionSettings.shared.isEnabled else {
            return
        }
        
        // Cancel existing next chapter task if different
        if let existing = nextChapterTask, existing.chapterIndex != chapterIndex {
            let cancelOldNextMsg = "🔄 [TranscriptionQueue] Cancelling old next chapter task: chapterIndex=\(existing.chapterIndex)"
            print(cancelOldNextMsg)
            FileLogger.shared.log(cancelOldNextMsg, category: "TranscriptionQueue")
            // Remove from queue if it's there
            queuedTasks.removeAll { $0.id == existing.id }
        }
        
        // Check if already in queue
        let existsInQueue = queuedTasks.contains { existingTask in
            existingTask.bookID == book.id && existingTask.chapterIndex == chapterIndex
        }
        
        if !existsInQueue {
            let task = TranscriptionTask(
                bookID: book.id,
                chapterIndex: chapterIndex,
                startTime: startTime,
                endTime: endTime,
                priority: .medium // Medium priority for next chapter
            )
            
            nextChapterTask = task
            queuedTasks.append(task)
            // Sort by priority (high first), then by creation time
            queuedTasks.sort { task1, task2 in
                if task1.priority != task2.priority {
                    return task1.priority > task2.priority
                }
                return task1.createdAt < task2.createdAt
            }
            
            let enqueueMsg = "📋 [TranscriptionQueue] ENQUEUED next chapter: bookID=\(book.id.uuidString), chapterIndex=\(chapterIndex), taskID=\(task.id.uuidString)"
            print(enqueueMsg)
            FileLogger.shared.log(enqueueMsg, category: "TranscriptionQueue")
        } else {
            // Already in queue, just mark it as next chapter task
            if let existing = queuedTasks.first(where: { $0.bookID == book.id && $0.chapterIndex == chapterIndex }) {
                nextChapterTask = existing
            }
        }
    }
    
    func isChapterQueuedOrRunning(bookID: UUID, chapterIndex: Int) async -> Bool {
        // Check if it's the current task
        if let current = currentTask, current.bookID == bookID && current.chapterIndex == chapterIndex {
            return true
        }
        
        // Check if it's in the queue
        return queuedTasks.contains { task in
            task.bookID == bookID && task.chapterIndex == chapterIndex
        }
    }
    
    // MARK: - Task Processing
    
    
    private func processNext() async {
        // Check if transcription is enabled
        guard TranscriptionSettings.shared.isEnabled else {
            return
        }
        
        // Don't process if already running a task
        guard currentTask == nil else {
            return
        }
        
        // Get next task from queue
        guard let nextTask = queuedTasks.first else {
            // No tasks in queue - this is normal, don't log
            return
        }
        
        // Remove from queue
        queuedTasks.removeFirst()
        
        // Set as current task
        currentTask = nextTask
        
        let startMsg1 = "▶️ [TranscriptionQueue] STARTING transcription task: taskID=\(nextTask.id.uuidString), bookID=\(nextTask.bookID.uuidString), chapterIndex=\(nextTask.chapterIndex), priority=\(nextTask.priority), retryCount=\(nextTask.retryCount)"
        let startMsg2 = "▶️ [TranscriptionQueue] Queue status: \(queuedTasks.count) queued, 1 running"
        print(startMsg1)
        print(startMsg2)
        FileLogger.shared.log(startMsg1, category: "TranscriptionQueue")
        FileLogger.shared.log(startMsg2, category: "TranscriptionQueue")
        
        // Start progress monitoring
        startProgressMonitoring(for: nextTask)
        
        // Execute transcription task
        currentTaskHandle = Task {
            await executeTask(nextTask)
            // Remove from running tasks when done
            await removeRunningTask(nextTask.id)
        }
    }
    
    private func executeTask(_ task: TranscriptionTask) async {
        // Fetch book from PersistenceManager
        let books = PersistenceManager.shared.loadBooks()
        guard let book = books.first(where: { $0.id == task.bookID }) else {
            print("❌ [TranscriptionQueue] EXECUTION FAILED - Book not found for task \(task.id.uuidString), bookID=\(task.bookID.uuidString)")
            await handleTaskFailure(task: task, error: nil)
            return
        }
        
        print("▶️ [TranscriptionQueue] EXECUTING task \(task.id.uuidString) for book '\(book.title)', chapterIndex=\(task.chapterIndex)")
        
        do {
            // Call transcribeChapter with the chapter index
            await TranscriptionManager.shared.transcribeChapter(book: book, chapterIndex: task.chapterIndex, startTime: task.startTime, endTime: task.endTime)
            
            // Check if task was cancelled
            try Task.checkCancellation()
            
            print("✅ [TranscriptionQueue] Task \(task.id.uuidString) execution completed")
        } catch {
            // Check if it was a cancellation (expected)
            if error is CancellationError {
                print("🚫 [TranscriptionQueue] Task \(task.id.uuidString) was cancelled")
                return // Don't retry on cancellation
            }
            
            // Task failed - handle retry
            print("❌ [TranscriptionQueue] Task \(task.id.uuidString) execution failed: \(error.localizedDescription)")
            await handleTaskFailure(task: task, error: error)
        }
    }
    
    private func handleTaskFailure(task: TranscriptionTask, error: Error?) async {
        // Check if we should retry
        if task.retryCount < maxRetries {
            let newRetryCount = task.retryCount + 1
            let retryDelay = 30.0 // 30 seconds backoff
            
            let retryMsg = "🔄 [TranscriptionQueue] Retrying task \(task.id.uuidString) (attempt \(newRetryCount + 1)/\(maxRetries + 1)) after \(retryDelay)s delay"
            print(retryMsg)
            FileLogger.shared.log(retryMsg, category: "TranscriptionQueue")
            
            // Wait before retry
            try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            
            // Create retry task with incremented retry count
            let retryTask = TranscriptionTask(
                bookID: task.bookID,
                chapterIndex: task.chapterIndex,
                startTime: task.startTime,
                endTime: task.endTime,
                priority: task.priority,
                retryCount: newRetryCount
            )
            
            // Add to front of queue (high priority)
            queuedTasks.insert(retryTask, at: 0)
            
            // Process next (which will be the retry)
            await processNext()
        } else {
            let failMsg = "❌ [TranscriptionQueue] Task \(task.id.uuidString) failed after \(maxRetries) retries - giving up"
            print(failMsg)
            FileLogger.shared.log(failMsg, category: "TranscriptionQueue")
        }
    }
    
    private func removeRunningTask(_ taskID: UUID) async {
        // Only remove if this is still the current task
        if let current = currentTask, current.id == taskID {
            currentTask = nil
            currentTaskHandle = nil
            progressMonitorTask?.cancel()
            progressMonitorTask = nil
            
            print("✅ [TranscriptionQueue] REMOVED task from running list: taskID=\(taskID.uuidString)")
            print("✅ [TranscriptionQueue] Queue status: \(queuedTasks.count) queued, 0 running")
            
            // Check if next chapter task is ready to start
            if let next = nextChapterTask,
               queuedTasks.contains(where: { $0.id == next.id }) {
                // Next chapter is in queue - it will be processed automatically
                // But we can prioritize it by moving it to front if needed
                // (Actually, it should already be at front if it's the only queued task)
                let nextReadyMsg = "📋 [TranscriptionQueue] Current chapter completed, next chapter ready: chapterIndex=\(next.chapterIndex)"
                print(nextReadyMsg)
                FileLogger.shared.log(nextReadyMsg, category: "TranscriptionQueue")
            }
            
            // Process next task if queue has items
            if !queuedTasks.isEmpty {
                await processNext()
            }
        }
    }
    
    // MARK: - Progress Monitoring
    
    private func startProgressMonitoring(for task: TranscriptionTask) {
        progressMonitorTask?.cancel()
        
        progressMonitorTask = Task {
            var lastSentenceCount = 0
            var lastProgressTime = Date()
            var hasReceivedFirstSentence = false
            
            while !Task.isCancelled {
                // Check current sentence count from TranscriptionManager
                let currentCount = await MainActor.run {
                    TranscriptionManager.shared.currentSentenceCount
                }
                
                let now = Date()
                let timeSinceLastProgress = now.timeIntervalSince(lastProgressTime)
                
                // Check if we got a new sentence
                if currentCount > lastSentenceCount {
                    lastSentenceCount = currentCount
                    lastProgressTime = now
                    hasReceivedFirstSentence = true
                    
                    let progressMsg = "📊 [TranscriptionQueue] Progress update for task \(task.id.uuidString): \(currentCount) sentences"
                    print(progressMsg)
                } else {
                    // No progress - check timeout
                    let timeout = hasReceivedFirstSentence ? progressTimeout : firstSentenceGracePeriod
                    
                    if timeSinceLastProgress >= timeout {
                        let timeoutMsg = "⏱️ [TranscriptionQueue] No progress for \(Int(timeSinceLastProgress))s (timeout: \(Int(timeout))s) - cancelling task \(task.id.uuidString)"
                        print(timeoutMsg)
                        FileLogger.shared.log(timeoutMsg, category: "TranscriptionQueue")
                        
                        // Cancel the task
                        currentTaskHandle?.cancel()
                        
                        // Handle as failure (will retry if under max retries)
                        await handleTaskFailure(task: task, error: TranscriptionError.timeout)
                        
                        // Remove from running
                        await removeRunningTask(task.id)
                        
                        return
                    }
                }
                
                // Check every 5 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
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
    
}
