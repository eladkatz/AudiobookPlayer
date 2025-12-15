import SwiftUI

@available(iOS 26.0, *)
struct AIMagicControlsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioManager = AudioManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @State private var highlightedSentenceID: UUID?
    @State private var isLoading = false
    @State private var nextStartTime: TimeInterval = 0
    @State private var isClearingDatabase = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    VStack(spacing: 12) {
                        Text("AI Magic Controls")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        if let book = appState.currentBook {
                            Text(book.title)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top)
                    
                    // Transcription Button
                    Button(action: {
                        guard let book = appState.currentBook else { return }
                        Task {
                            await transcriptionManager.transcribeNextTwoMinutes(book: book)
                            // Update next start time after transcription
                            if let book = appState.currentBook {
                                nextStartTime = await TranscriptionDatabase.shared.getNextTranscriptionStartTime(bookID: book.id)
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "waveform")
                            Text(buttonText)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            transcriptionManager.isTranscribing || appState.currentBook == nil
                                ? Color.gray
                                : Color.blue
                        )
                        .cornerRadius(12)
                    }
                    .disabled(transcriptionManager.isTranscribing || appState.currentBook == nil)
                    .padding(.horizontal)
                    
                    // Clear Database Button (for debugging)
                    Button(action: {
                        guard let book = appState.currentBook else { return }
                        Task {
                            isClearingDatabase = true
                            await TranscriptionDatabase.shared.clearTranscription(bookID: book.id)
                            nextStartTime = 0
                            transcriptionManager.transcribedSentences = []
                            isClearingDatabase = false
                        }
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text(isClearingDatabase ? "Clearing..." : "Clear Database")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            isClearingDatabase || transcriptionManager.isTranscribing || appState.currentBook == nil
                                ? Color.gray
                                : Color.red
                        )
                        .cornerRadius(12)
                    }
                    .disabled(isClearingDatabase || transcriptionManager.isTranscribing || appState.currentBook == nil)
                    .padding(.horizontal)
                    
                    // Status and Progress
                    if transcriptionManager.isTranscribing {
                        VStack(spacing: 8) {
                            Text(transcriptionManager.currentStatus)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: transcriptionManager.progress)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            Text("\(Int(transcriptionManager.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Error Message
                    if let error = transcriptionManager.errorMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.title2)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Loading State
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading transcription...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    }
                    
                    // Transcription Results
                    else if !transcriptionManager.transcribedSentences.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Transcription Results")
                                    .font(.headline)
                                Spacer()
                                Text("\(transcriptionManager.transcribedSentences.count) sentences")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            
                            // SRT Format Display with ScrollViewReader for auto-scrolling
                            ScrollViewReader { proxy in
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(transcriptionManager.transcribedSentences.enumerated()), id: \.element.id) { index, sentence in
                                        VStack(alignment: .leading, spacing: 4) {
                                            // SRT sequence number and timestamp
                                            Text("\(index + 1)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text(sentence.srtTimeString)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            
                                            // Sentence text
                                            Text(sentence.text)
                                                .font(.body)
                                                .padding(.top, 2)
                                        }
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            highlightedSentenceID == sentence.id
                                                ? Color.blue.opacity(0.15)
                                                : Color.clear
                                        )
                                        .cornerRadius(8)
                                        .id(sentence.id)
                                        
                                        Divider()
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                                .onChange(of: highlightedSentenceID) { oldID, newID in
                                    // Scroll to highlighted sentence when it changes
                                    if let newID = newID {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo(newID, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Empty State
                    else if !transcriptionManager.isTranscribing &&
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
                            
                            Text("Tap the button above to transcribe 2-minute segments of the audiobook")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("AI Magic")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Load existing transcription and determine next start time
                if let book = appState.currentBook {
                    print("📱 [AIMagicControlsView] onAppear: Loading sentences for book \(book.id.uuidString)")
                    isLoading = true
                    // Load all transcribed sentences
                    await transcriptionManager.loadSentencesForDisplay(
                        bookID: book.id,
                        startTime: 0,
                        endTime: Double.greatestFiniteMagnitude
                    )
                    // Query next start time
                    nextStartTime = await TranscriptionDatabase.shared.getNextTranscriptionStartTime(bookID: book.id)
                    print("📱 [AIMagicControlsView] onAppear: Loaded \(transcriptionManager.transcribedSentences.count) sentences, next start: \(nextStartTime)s")
                    isLoading = false
                }
            }
            .onChange(of: appState.currentBook?.id) { oldID, newID in
                // Reload when book changes
                if let bookID = newID {
                    Task {
                        isLoading = true
                        await transcriptionManager.loadSentencesForDisplay(
                            bookID: bookID,
                            startTime: 0,
                            endTime: Double.greatestFiniteMagnitude
                        )
                        nextStartTime = await TranscriptionDatabase.shared.getNextTranscriptionStartTime(bookID: bookID)
                        isLoading = false
                    }
                }
            }
            .onChange(of: audioManager.currentTime) { oldTime, newTime in
                // Sync highlighting for all transcribed sentences (no time limit)
                guard audioManager.isPlaying,
                      !transcriptionManager.transcribedSentences.isEmpty else {
                    highlightedSentenceID = nil
                    return
                }
                
                // Find the sentence that matches current playback time
                if let currentSentence = transcriptionManager.transcribedSentences.first(where: { sentence in
                    newTime >= sentence.startTime && newTime <= sentence.endTime
                }) {
                    highlightedSentenceID = currentSentence.id
                } else {
                    // If no exact match, find the closest sentence
                    if let closestSentence = transcriptionManager.transcribedSentences.min(by: { sentence1, sentence2 in
                        let diff1 = abs(sentence1.startTime - newTime)
                        let diff2 = abs(sentence2.startTime - newTime)
                        return diff1 < diff2
                    }), abs(closestSentence.startTime - newTime) < 2.0 { // Within 2 seconds
                        highlightedSentenceID = closestSentence.id
                    } else {
                        highlightedSentenceID = nil
                    }
                }
            }
            .onChange(of: audioManager.isPlaying) { oldValue, newValue in
                // Clear highlight when playback stops
                if !newValue {
                    highlightedSentenceID = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if transcriptionManager.isTranscribing {
                        Button("Cancel") {
                            transcriptionManager.cancel()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var buttonText: String {
        let startMinutes = Int(nextStartTime) / 60
        let startSeconds = Int(nextStartTime) % 60
        let endMinutes = (Int(nextStartTime) + 120) / 60
        let endSeconds = (Int(nextStartTime) + 120) % 60
        return "Transcribe 2 Minutes (\(startMinutes):\(String(format: "%02d", startSeconds))-\(endMinutes):\(String(format: "%02d", endSeconds)))"
    }
}


