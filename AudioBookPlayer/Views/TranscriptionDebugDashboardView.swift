import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct TranscriptionDebugDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var tracker = TranscriptionInstanceTracker.shared
    @State private var queuedTasks: [TranscriptionQueue.TranscriptionTask] = []
    @State private var runningTasks: [TranscriptionQueue.TranscriptionTask] = []
    @State private var queueStatus: (queued: Int, running: Int, maxConcurrent: Int) = (0, 0, 0)
    @State private var refreshTimer: Timer?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Metrics Section
                    metricsSection
                    
                    // Queue Status Section
                    queueStatusSection
                    
                    // Running Instances Section
                    runningInstancesSection
                    
                    // All Instances Section
                    allInstancesSection
                }
                .padding()
            }
            .navigationTitle("Transcription Debug")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshData()
                startRefreshTimer()
            }
            .onDisappear {
                stopRefreshTimer()
            }
        }
    }
    
    // MARK: - Metrics Section
    
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                // Use updateTrigger to force SwiftUI to observe changes
                let _ = tracker.updateTrigger
                MetricRow(label: "Total Instances", value: "\(tracker.instances.count)")
                MetricRow(label: "Running Now", value: "\(tracker.totalRunningCount)")
                MetricRow(label: "Completed", value: "\(tracker.completedInstances.count)")
                MetricRow(label: "Failed", value: "\(tracker.failedInstances.count)")
                MetricRow(label: "Average Duration", value: String(format: "%.2fs", tracker.averageDuration))
                MetricRow(label: "Battery Impact", value: tracker.estimatedBatteryImpact)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Queue Status Section
    
    private var queueStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue Status")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(label: "Queued Tasks", value: "\(queueStatus.queued)")
                MetricRow(label: "Running Tasks", value: "\(queueStatus.running)")
                MetricRow(label: "Max Concurrent", value: "\(queueStatus.maxConcurrent)")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            if !queuedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Queued Tasks:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ForEach(queuedTasks.prefix(10)) { task in
                        QueuedTaskRow(task: task)
                    }
                    
                    if queuedTasks.count > 10 {
                        Text("... and \(queuedTasks.count - 10) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Running Instances Section
    
    private var runningInstancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Running Instances")
                .font(.headline)
            
            // Force observation of tracker changes
            let _ = tracker.updateTrigger
            let running = tracker.runningInstances
            
            if running.isEmpty {
                Text("No instances currently running")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            } else {
                ForEach(running) { instance in
                    InstanceRow(instance: instance)
                }
            }
        }
    }
    
    // MARK: - All Instances Section
    
    private var allInstancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Force observation of tracker changes
            let _ = tracker.updateTrigger
            let allInstances = tracker.instances
            
            Text("All Instances (\(allInstances.count))")
                .font(.headline)
            
            if allInstances.isEmpty {
                Text("No instances recorded")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            } else {
                ForEach(allInstances.reversed()) { instance in
                    InstanceRow(instance: instance)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func refreshData() {
        Task {
                let queue = TranscriptionQueue.shared
                queuedTasks = await queue.getQueuedTasks()
                runningTasks = await queue.getRunningTasks()
                queueStatus = await queue.getQueueStatus()
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshData()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Views

@available(iOS 26.0, *)
struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

@available(iOS 26.0, *)
struct InstanceRow: View {
    let instance: TranscriptionInstanceTracker.TranscriptionInstance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusIndicator
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.bookTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(instance.chapterTitle) • \(instance.timeRangeFormatted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack {
                Text("Started: \(formatDate(instance.startedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let endedAt = instance.endedAt {
                    Text("Ended: \(formatDate(endedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Still running...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            if let duration = instance.duration {
                Text("Duration: \(String(format: "%.2f", duration))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Sentences: \(instance.sentenceCount)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let error = instance.errorMessage {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch instance.status {
        case .running:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .gray
        }
    }
    
    private var backgroundColor: Color {
        switch instance.status {
        case .running:
            return Color.orange.opacity(0.1)
        case .completed:
            return Color.green.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        case .cancelled:
            return Color(.systemGray6)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

@available(iOS 26.0, *)
struct QueuedTaskRow: View {
    let task: TranscriptionQueue.TranscriptionTask
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTime(task.startTime))
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Priority: \(task.priority.rawValue)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formatDate(task.createdAt))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}


