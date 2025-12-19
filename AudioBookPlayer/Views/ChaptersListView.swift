import SwiftUI

struct ChaptersListView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioManager = AudioManager.shared
    @State private var transcriptionStatus: [UUID: ChapterTranscriptionStatus] = [:]
    
    enum ChapterTranscriptionStatus {
        case transcribed
        case transcribing
        case notTranscribed
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if audioManager.chapters.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No chapters available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(Array(audioManager.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(action: {
                                audioManager.seek(to: chapter.startTime)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chapter.title)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Text(formatTime(chapter.startTime))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        // Transcription status indicator
                                        if #available(iOS 26.0, *) {
                                            transcriptionStatusIcon(for: chapter.id)
                                        }
                                        
                                        // Current chapter indicator
                                    if index == audioManager.currentChapterIndex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .padding()
                                .background(
                                    index == audioManager.currentChapterIndex
                                        ? Color.blue.opacity(0.1)
                                        : Color(.systemGray6)
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if #available(iOS 26.0, *) {
                    loadTranscriptionStatus()
                }
            }
            .onChange(of: audioManager.chapters.count) { _, _ in
                if #available(iOS 26.0, *) {
                    loadTranscriptionStatus()
                }
            }
        }
    }
    
    @available(iOS 26.0, *)
    @ViewBuilder
    private func transcriptionStatusIcon(for chapterID: UUID) -> some View {
        let status = transcriptionStatus[chapterID] ?? .notTranscribed
        
        switch status {
        case .transcribed:
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundColor(.green)
        case .transcribing:
            ProgressView()
                .scaleEffect(0.7)
        case .notTranscribed:
            Image(systemName: "waveform.slash")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    @available(iOS 26.0, *)
    private func loadTranscriptionStatus() {
        guard let book = appState.currentBook else {
            return
        }
        
        Task {
            var newStatus: [UUID: ChapterTranscriptionStatus] = [:]
            
            for chapter in audioManager.chapters {
                // Check if transcribed
                let isTranscribed = await TranscriptionDatabase.shared.isChapterTranscribed(
                    bookID: book.id,
                    chapterID: chapter.id
                )
                
                if isTranscribed {
                    newStatus[chapter.id] = .transcribed
                } else {
                    // Check if currently transcribing
                    let isTranscribing = await TranscriptionDatabase.shared.isChapterTranscribing(
                        bookID: book.id,
                        chapterID: chapter.id
                    )
                    
                    newStatus[chapter.id] = isTranscribing ? .transcribing : .notTranscribed
                }
            }
            
            await MainActor.run {
                transcriptionStatus = newStatus
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}




