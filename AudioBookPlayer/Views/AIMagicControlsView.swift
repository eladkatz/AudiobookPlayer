import SwiftUI

@available(iOS 26.0, *)
struct AIMagicControlsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioManager = AudioManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @State private var highlightedSentenceID: UUID?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top 80% - Transcription content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if isLoading {
                                loadingStateView
                            } else if !transcriptionManager.transcribedSentences.isEmpty {
                                transcriptionContentView
                                    .onChange(of: highlightedSentenceID) { oldID, newID in
                                        if let newID = newID {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                proxy.scrollTo(newID, anchor: UnitPoint.center)
                                            }
                                        }
                                    }
                            } else {
                                emptyStateView
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: .infinity)
                }
                
                // Bottom 20% - "What did I miss?" button
                VStack {
                    Button(action: {
                        // Placeholder - does nothing for now
                    }) {
                        Text("What did I miss?")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .frame(height: UIScreen.main.bounds.height * 0.2)
                .background(Color(.systemBackground))
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                loadInitialSentences()
            }
            .onChange(of: appState.currentBook?.id) { oldID, newID in
                handleBookChange(newID: newID)
            }
            .onChange(of: audioManager.currentTime) { oldTime, newTime in
                updateHighlight(for: newTime)
            }
            .onChange(of: audioManager.isPlaying) { oldValue, newValue in
                if !newValue {
                    highlightedSentenceID = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Navigation Title
    
    private var navigationTitle: String {
        if transcriptionManager.isTranscribing {
            let emoji = statusEmoji(for: transcriptionManager.currentStatus)
            return "\(emoji) \(shortStatusText(for: transcriptionManager.currentStatus))"
        }
        return "AI Magic"
    }
    
    private func statusEmoji(for status: String) -> String {
        if status.contains("Preparing") {
            return "⚙️"
        } else if status.contains("language model") || status.contains("Checking") {
            return "📚"
        } else if status.contains("Extracting") || status.contains("audio segment") {
            return "✂️"
        } else if status.contains("Transcribing") {
            return "🎤"
        } else if status.contains("Inserting") || status.contains("database") {
            return "💾"
        } else if status.contains("complete") || status.contains("Complete") {
            return "✅"
        }
        return "🔄"
    }
    
    private func shortStatusText(for status: String) -> String {
        if status.contains("Preparing") {
            return "Preparing..."
        } else if status.contains("language model") || status.contains("Checking") {
            return "Checking model..."
        } else if status.contains("Extracting") || status.contains("audio segment") {
            return "Extracting..."
        } else if status.contains("Transcribing") {
            return "Transcribing..."
        } else if status.contains("Inserting") || status.contains("database") {
            return "Saving..."
        } else if status.contains("complete") || status.contains("Complete") {
            return "Complete"
        }
        return "Processing..."
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading transcription...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    @ViewBuilder
    private var transcriptionContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(transcriptionManager.transcribedSentences, id: \.id) { sentence in
                sentenceRow(sentence: sentence)
                Divider()
            }
        }
    }
    
    private func sentenceRow(sentence: TranscribedSentence) -> some View {
        Text(sentence.text)
            .font(.body)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                highlightedSentenceID == sentence.id
                    ? Color.blue.opacity(0.15)
                    : Color.clear
            )
            .cornerRadius(8)
            .id(sentence.id)
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        if !transcriptionManager.isTranscribing &&
           !isLoading &&
           transcriptionManager.transcribedSentences.isEmpty &&
           transcriptionManager.errorMessage == nil {
            VStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("No transcription yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Transcription will appear automatically as you listen to the audiobook")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadInitialSentences() {
        Task {
            if let book = appState.currentBook {
                isLoading = true
                let centerTime = audioManager.currentTime
                let windowSize: TimeInterval = 75.0
                let startTime = max(0, centerTime - 30.0)
                let endTime = centerTime + windowSize
                
                await transcriptionManager.loadSentencesForDisplay(
                    bookID: book.id,
                    startTime: startTime,
                    endTime: endTime
                )
                isLoading = false
            }
        }
    }
    
    private func handleBookChange(newID: UUID?) {
        if let bookID = newID {
            Task {
                isLoading = true
                let centerTime = audioManager.currentTime
                let windowSize: TimeInterval = 75.0
                let startTime = max(0, centerTime - 30.0)
                let endTime = centerTime + windowSize
                
                await transcriptionManager.loadSentencesForDisplay(
                    bookID: bookID,
                    startTime: startTime,
                    endTime: endTime
                )
                isLoading = false
            }
        }
    }
    
    private func updateHighlight(for newTime: TimeInterval) {
        guard audioManager.isPlaying,
              !transcriptionManager.transcribedSentences.isEmpty else {
            highlightedSentenceID = nil
            return
        }
        
        if let currentSentence = transcriptionManager.transcribedSentences.first(where: { sentence in
            newTime >= sentence.startTime && newTime <= sentence.endTime
        }) {
            highlightedSentenceID = currentSentence.id
        } else {
            if let closestSentence = transcriptionManager.transcribedSentences.min(by: { sentence1, sentence2 in
                let diff1 = abs(sentence1.startTime - newTime)
                let diff2 = abs(sentence2.startTime - newTime)
                return diff1 < diff2
            }), abs(closestSentence.startTime - newTime) < 2.0 {
                highlightedSentenceID = closestSentence.id
            } else {
                highlightedSentenceID = nil
            }
        }
    }
}
