import SwiftUI

@available(iOS 26.0, *)
struct AIMagicControlsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioManager = AudioManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var transcriptionSettings = TranscriptionSettings.shared
    @State private var isLoading = false
    
    // MARK: - Reload State Management (Infinite Loop Prevention)
    @State private var reloadTask: Task<Void, Never>?
    @State private var isReloading = false
    @State private var lastReloadTime: Date?
    @State private var reloadAttemptCount = 0
    private let maxReloadAttempts = 2
    private let reloadDebounceInterval: TimeInterval = 3.0
    
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
                } else if transcriptionManager.isTranscribing {
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
        .onChange(of: audioManager.currentTime) { oldTime, newTime in
            updateCurrentSentence(for: newTime)
        }
    }
    
    // MARK: - Current Sentence
    
    @State private var currentSentence: TranscribedSentence?
    
    private func updateCurrentSentence(for time: TimeInterval) {
        // Guard: Prevent reloads when transcription is disabled
        guard transcriptionSettings.isEnabled else {
            print("🚫 [AIMagicControlsView] updateCurrentSentence: Transcription disabled, skipping")
            return
        }
        
        // Guard: Debounce rapid calls
        if let lastReload = lastReloadTime {
            let timeSinceLastReload = Date().timeIntervalSince(lastReload)
            if timeSinceLastReload < reloadDebounceInterval {
                print("⏸️ [AIMagicControlsView] updateCurrentSentence: Debouncing rapid call (last reload was \(String(format: "%.2f", timeSinceLastReload))s ago)")
                return
            }
        }
        
        guard !transcriptionManager.transcribedSentences.isEmpty else {
            print("⚠️ [AIMagicControlsView] updateCurrentSentence: No sentences loaded at time \(time)s")
            currentSentence = nil
            // Try to reload sentences if we have a book
            if let book = appState.currentBook {
                Task {
                    await reloadSentencesAround(time: time, bookID: book.id)
                }
            }
            return
        }
        
        // Check if current time is within loaded sentence range
        let loadedStart = transcriptionManager.transcribedSentences.first?.startTime ?? 0
        let loadedEnd = transcriptionManager.transcribedSentences.last?.endTime ?? 0
        let isWithinLoadedRange = time >= loadedStart && time <= loadedEnd
        
        // Find sentence that contains current time
        if let sentence = transcriptionManager.transcribedSentences.first(where: { sentence in
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
            if let closestSentence = transcriptionManager.transcribedSentences.min(by: { sentence1, sentence2 in
                let diff1 = abs(sentence1.startTime - time)
                let diff2 = abs(sentence2.startTime - time)
                return diff1 < diff2
            }), abs(closestSentence.startTime - time) < 2.0 {
                print("✅ [AIMagicControlsView] updateCurrentSentence: Using closest sentence (within 2s) at \(time)s - '\(closestSentence.text.prefix(50))...' [\(closestSentence.startTime)s-\(closestSentence.endTime)s]")
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentSentence = closestSentence
                }
            } else {
                // No sentence found - check if we need to reload for new time range
                if !isWithinLoadedRange {
                    print("⚠️ [AIMagicControlsView] updateCurrentSentence: Time \(time)s is outside loaded range [\(loadedStart)s-\(loadedEnd)s], reloading...")
                    currentSentence = nil
                    if let book = appState.currentBook {
                        Task {
                            await reloadSentencesAround(time: time, bookID: book.id)
                        }
                    }
                } else {
                    print("⚠️ [AIMagicControlsView] updateCurrentSentence: No sentence found at \(time)s (within loaded range [\(loadedStart)s-\(loadedEnd)s]) - gap in transcription")
                    currentSentence = nil
                }
            }
        }
    }
    
    private func reloadSentencesAround(time: TimeInterval, bookID: UUID) async {
        // Prevention: Track attempts and prevent concurrent reloads
        await MainActor.run {
            // Check if already reloading
            if isReloading {
                print("⏸️ [AIMagicControlsView] reloadSentencesAround: Already reloading, skipping")
                return
            }
            
            // Check if max attempts reached
            if reloadAttemptCount >= maxReloadAttempts {
                print("🚫 [AIMagicControlsView] reloadSentencesAround: Max reload attempts (\(maxReloadAttempts)) reached, skipping")
                return
            }
            
            // Cancel previous reload task if exists
            reloadTask?.cancel()
            
            // Mark as reloading and increment attempt count
            isReloading = true
            reloadAttemptCount += 1
            lastReloadTime = Date()
        }
        
        print("🔄 [AIMagicControlsView] Reloading sentences around time \(time)s (attempt \(reloadAttemptCount)/\(maxReloadAttempts))")
        let windowSize: TimeInterval = 300.0 // 5 minutes window
        let startTime = max(0, time - 60.0)
        let endTime = time + windowSize
        
        await transcriptionManager.loadSentencesForDisplay(
            bookID: bookID,
            startTime: startTime,
            endTime: endTime
        )
        
        let sentenceCount = transcriptionManager.transcribedSentences.count
        print("🔄 [AIMagicControlsView] Reloaded \(sentenceCount) sentences, range: \(startTime)s-\(endTime)s")
        
        // CRITICAL FIX: Do NOT call updateCurrentSentence() again if 0 sentences are loaded
        // This breaks the infinite loop - if no sentences were loaded, calling updateCurrentSentence()
        // would trigger another reload, creating an infinite loop
        await MainActor.run {
            isReloading = false
            
            if sentenceCount > 0 {
                // Only update if we actually loaded sentences
                updateCurrentSentence(for: time)
                // Reset attempt count on success
                reloadAttemptCount = 0
            } else {
                print("⚠️ [AIMagicControlsView] reloadSentencesAround: No sentences loaded, NOT calling updateCurrentSentence() to prevent infinite loop")
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
        Task {
            if let book = appState.currentBook {
                isLoading = true
                var centerTime = audioManager.currentTime
                
                // Load wider window to ensure we have sentences available for current time tracking
                let windowSize: TimeInterval = 300.0 // 5 minutes window
                var startTime = max(0, centerTime - 60.0)
                var endTime = centerTime + windowSize
                
                await transcriptionManager.loadSentencesForDisplay(
                    bookID: book.id,
                    startTime: startTime,
                    endTime: endTime
                )
                
                // Check if loaded sentences actually cover the current time
                // (currentTime might have been 0.0 when view appeared, but book loads later)
                let actualCurrentTime = audioManager.currentTime
                let sentencesCoverCurrentTime = transcriptionManager.transcribedSentences.contains { sentence in
                    actualCurrentTime >= sentence.startTime && actualCurrentTime <= sentence.endTime
                }
                
                // If sentences don't cover current time, reload around actual current time
                if !sentencesCoverCurrentTime && actualCurrentTime > 0 {
                    print("⚠️ [AIMagicControlsView] Loaded sentences (range: \(startTime)s-\(endTime)s) don't cover current time (\(actualCurrentTime)s), reloading...")
                    centerTime = actualCurrentTime
                    startTime = max(0, centerTime - 60.0)
                    endTime = centerTime + windowSize
                    
                    await transcriptionManager.loadSentencesForDisplay(
                        bookID: book.id,
                        startTime: startTime,
                        endTime: endTime
                    )
                }
                
                // Update current sentence after loading
                updateCurrentSentence(for: actualCurrentTime)
                
                // If no sentences loaded, try loading from the beginning (fallback for existing transcriptions)
                if transcriptionManager.transcribedSentences.isEmpty {
                    let progress = await transcriptionManager.getTranscriptionProgress(bookID: book.id)
                    if progress > 0 {
                        await transcriptionManager.loadSentencesForDisplay(
                            bookID: book.id,
                            startTime: 0,
                            endTime: progress + 60.0
                        )
                        updateCurrentSentence(for: actualCurrentTime)
                    }
                    
                    // If still no sentences (or progress is 0), trigger transcription check
                    if transcriptionManager.transcribedSentences.isEmpty {
                        audioManager.checkAndTriggerTranscriptionForSeek(time: actualCurrentTime)
                    }
                } else if currentSentence == nil {
                    // Sentences loaded but none match current time - might be a gap
                    print("⚠️ [AIMagicControlsView] Sentences loaded (\(transcriptionManager.transcribedSentences.count) sentences) but none match current time (\(actualCurrentTime)s)")
                    print("⚠️ [AIMagicControlsView] Loaded sentence range: \(transcriptionManager.transcribedSentences.first?.startTime ?? 0)s - \(transcriptionManager.transcribedSentences.last?.endTime ?? 0)s")
                }
                
                isLoading = false
            }
        }
    }
    
    private func handleBookChange(newID: UUID?) {
        if let bookID = newID {
            Task {
                isLoading = true
                let centerTime = audioManager.currentTime
                // Load wider window to ensure we have sentences available
                let windowSize: TimeInterval = 300.0 // 5 minutes window
                let startTime = max(0, centerTime - 60.0)
                let endTime = centerTime + windowSize
                
                await transcriptionManager.loadSentencesForDisplay(
                    bookID: bookID,
                    startTime: startTime,
                    endTime: endTime
                )
                
                // Update current sentence after loading
                updateCurrentSentence(for: centerTime)
                
                isLoading = false
            }
        }
    }
}
