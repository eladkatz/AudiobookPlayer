import SwiftUI

@available(iOS 26.0, *)
struct AIMagicControlsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioManager = AudioManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var transcriptionSettings = TranscriptionSettings.shared
    @State private var isLoading = false
    
    var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            let isCompact = geometry.size.width < 400 // iPhone SE and smaller
            
            VStack(spacing: 0) {
                // Check if transcription is disabled first
                if !transcriptionSettings.isEnabled {
                    disabledStateView
                } else if isLoading {
                    loadingStateView
                } else if transcriptionManager.isTranscribing && isCurrentChapterTranscribing {
                    // Only show "Transcribing..." if the current chapter is being transcribed
                    transcribingStateView
                } else if let currentSentence = currentSentence {
                    // Show current sentence (captions style)
                    // Adaptive layout: more lines in portrait, fewer in landscape
                    adaptiveSentenceView(
                        sentence: currentSentence,
                        isPortrait: isPortrait,
                        isCompact: isCompact
                    )
                } else {
                    // No transcription available
                    errorStateView
                }
            }
            .frame(minHeight: 60)
        }
        .task {
            loadInitialSentences()
        }
        .onChange(of: appState.currentBook?.id) { oldID, newID in
            handleBookChange(newID: newID)
        }
        .onChange(of: audioManager.currentChapterIndex) { oldIndex, newIndex in
            loadSentencesForCurrentChapter()
        }
        .onChange(of: transcriptionManager.isTranscribing) { oldValue, newValue in
            // When transcription completes (transitions from true to false), reload sentences
            if oldValue == true && newValue == false {
                print("🔄 [AIMagicControlsView] Transcription completed - reloading sentences for current chapter")
                loadSentencesForCurrentChapter()
            }
        }
        .onChange(of: audioManager.currentTime) { oldTime, newTime in
            updateCurrentSentence(for: newTime)
        }
    }
    
    // MARK: - Current Sentence
    
    @State private var currentSentence: TranscribedSentence?
    
    // Check if the current chapter is the one being transcribed
    private var isCurrentChapterTranscribing: Bool {
        guard let currentChapterID = getCurrentChapterID(),
              let transcribingChapterID = transcriptionManager.currentTranscribingChapterID else {
            return false
        }
        return currentChapterID == transcribingChapterID
    }
    
    private func getCurrentChapterID() -> UUID? {
        let currentChapterIndex = audioManager.currentChapterIndex
        guard currentChapterIndex >= 0 && currentChapterIndex < audioManager.chapters.count else {
            return nil
        }
        return audioManager.chapters[currentChapterIndex].id
    }
    
    private func updateCurrentSentence(for time: TimeInterval) {
        // Guard: Prevent when transcription is disabled
        guard transcriptionSettings.isEnabled else {
            return
        }
        
        // Create a local copy to avoid threading issues
        let sentences = Array(transcriptionManager.transcribedSentences)
        
        guard !sentences.isEmpty else {
            // No sentences loaded - chapter might be transcribing
            currentSentence = nil
            return
        }
        
        // Find sentence that contains current time
        if let sentence = sentences.first(where: { sentence in
            time >= sentence.startTime && time <= sentence.endTime
        }) {
            if currentSentence?.id != sentence.id {
                print("✅ [AIMagicControlsView] updateCurrentSentence: Found sentence at \(time)s - '\(sentence.text.prefix(50))...' [\(sentence.startTime)s-\(sentence.endTime)s]")
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                currentSentence = sentence
            }
        } else {
            // If no exact match, find closest sentence within 2 seconds
            // Additional safety check
            guard sentences.count > 0 else {
                currentSentence = nil
                return
            }
            
            if let closestSentence = sentences.min(by: { sentence1, sentence2 in
                let diff1 = abs(sentence1.startTime - time)
                let diff2 = abs(sentence2.startTime - time)
                return diff1 < diff2
            }), abs(closestSentence.startTime - time) < 2.0 {
                print("✅ [AIMagicControlsView] updateCurrentSentence: Using closest sentence (within 2s) at \(time)s - '\(closestSentence.text.prefix(50))...' [\(closestSentence.startTime)s-\(closestSentence.endTime)s]")
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentSentence = closestSentence
                }
            } else {
                // No sentence found - might be gap in transcription or chapter is still transcribing
                print("⚠️ [AIMagicControlsView] updateCurrentSentence: No sentence found at \(time)s - chapter might be transcribing")
                    currentSentence = nil
                }
        }
    }
    
    private func loadSentencesForCurrentChapter() {
        Task {
            guard let book = appState.currentBook else { return }
            
            let currentChapterIndex = audioManager.currentChapterIndex
            guard currentChapterIndex >= 0 && currentChapterIndex < audioManager.chapters.count else {
                return
            }
            
            let chapter = audioManager.chapters[currentChapterIndex]
            
            // Load sentences for current chapter
            let sentences = await transcriptionManager.loadSentencesForChapter(
                bookID: book.id,
                chapterID: chapter.id
            )
        
            // Update UI
        await MainActor.run {
                transcriptionManager.transcribedSentences = sentences
                updateCurrentSentence(for: audioManager.currentTime)
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func adaptiveSentenceView(sentence: TranscribedSentence, isPortrait: Bool, isCompact: Bool) -> some View {
        // Adaptive line limit based on orientation and screen size
        let lineLimit: Int? = {
            if isPortrait {
                return isCompact ? 5 : 6 // More lines in portrait
            } else {
                return isCompact ? 3 : 4 // Fewer lines in landscape
            }
        }()
        
        // Adaptive font size
        let fontSize: CGFloat = {
            if isPortrait {
                return isCompact ? 16 : 18
            } else {
                return isCompact ? 14 : 16 // Smaller in landscape for more text
            }
        }()
        
        // Max height cap - allows scrolling if content exceeds
        let maxHeight: CGFloat = isPortrait ? 200 : 150
        
        ScrollView {
            Text(sentence.text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isPortrait ? 20 : 24)
                .padding(.vertical, 16)
        }
        .frame(maxHeight: maxHeight)
        .transition(.opacity)
    }
    
    @ViewBuilder
    private var loadingStateView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading transcription...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private var transcribingStateView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Transcribing...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private var disabledStateView: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .foregroundColor(.red)
            Text("Transcription is turned off")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private var errorStateView: some View {
        if let errorMessage = transcriptionManager.errorMessage {
            // Show error message if available
            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .onAppear {
                    print("⚠️ [AIMagicControlsView] ERROR STATE: Showing error message - '\(errorMessage)'")
                    print("⚠️ [AIMagicControlsView] Error details: isTranscribing=\(transcriptionManager.isTranscribing), sentencesCount=\(transcriptionManager.transcribedSentences.count), isLoading=\(isLoading)")
                }
        } else {
            // No transcription available yet
            Text("Not yet transcribed")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .onAppear {
                    print("⚠️ [AIMagicControlsView] ERROR STATE: Showing 'Not yet transcribed'")
                    print("⚠️ [AIMagicControlsView] State details: isTranscribing=\(transcriptionManager.isTranscribing), sentencesCount=\(transcriptionManager.transcribedSentences.count), isLoading=\(isLoading), errorMessage=\(transcriptionManager.errorMessage ?? "nil")")
                    if let book = appState.currentBook {
                        Task {
                            let progress = await transcriptionManager.getTranscriptionProgress(bookID: book.id)
                            print("⚠️ [AIMagicControlsView] Transcription progress for book '\(book.title)': \(progress)s")
                            if progress == 0 {
                                print("⚠️ [AIMagicControlsView] No transcription exists yet - transcription may need to be triggered")
                            } else {
                                print("⚠️ [AIMagicControlsView] Transcription exists (progress=\(progress)s) but no sentences loaded at current time (\(audioManager.currentTime)s)")
                            }
                        }
                    }
                }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadInitialSentences() {
        loadSentencesForCurrentChapter()
    }
    
    private func handleBookChange(newID: UUID?) {
        if newID != nil {
            loadSentencesForCurrentChapter()
        }
    }
}
