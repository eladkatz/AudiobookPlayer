import SwiftUI

@available(iOS 26.0, *)
struct AIMagicControlsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioManager = AudioManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @State private var highlightedSentenceID: UUID?
    
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
                            await transcriptionManager.transcribeFirstFiveMinutes(book: book)
                        }
                    }) {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Transcribe First 5 Minutes")
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
                    
                    // Transcription Results
                    if !transcriptionManager.transcribedSentences.isEmpty {
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
                    if !transcriptionManager.isTranscribing &&
                       transcriptionManager.transcribedSentences.isEmpty &&
                       transcriptionManager.errorMessage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No transcription yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Tap the button above to transcribe the first 5 minutes of the audiobook")
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
            .onChange(of: audioManager.currentTime) { oldTime, newTime in
                // Only sync if playing and within first 5 minutes
                guard audioManager.isPlaying,
                      newTime <= 5 * 60, // First 5 minutes only
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
                    // (in case timestamps don't perfectly align)
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
}
