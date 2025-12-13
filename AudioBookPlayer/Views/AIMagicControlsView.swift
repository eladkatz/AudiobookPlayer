import SwiftUI

@available(iOS 26.0, *)
struct AIMagicControlsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    
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
                            
                            // SRT Format Display
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
                                    
                                    Divider()
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
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
