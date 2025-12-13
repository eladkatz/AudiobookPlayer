import SwiftUI

struct PlayerView: View {
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var appState: AppState
    @ObservedObject private var coverManager = CoverImageManager.shared
    @State private var showSpeedPicker = false
    @State private var showSleepTimerPicker = false
    @State private var showAIMagicControls = false
    
    var body: some View {
        Group {
            if appState.currentBook != nil {
                playerContent
            } else {
                emptyPlayerView
            }
        }
    }
    
    private var playerContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    // Error Message
                    if let error = audioManager.playbackError {
                        errorSection(error)
                    }
                    
                    // Cover Art Area
                    coverArtSection(availableWidth: geometry.size.width)
                    
                    // Book Info
                    bookInfoSection
                    
                    // Progress Slider
                    progressSection
                    
                    // Time Display
                    timeDisplaySection
                    
                    // Control Buttons
                    controlButtonsSection(availableWidth: geometry.size.width)
                    
                    // Chapter Navigation
                    chapterNavigationSection(availableWidth: geometry.size.width)
                    
                    // Bottom padding for scroll and tab bar
                    Spacer()
                        .frame(height: 24)
                }
                .padding(.horizontal, 16)
                .frame(width: geometry.size.width)
            }
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showAIMagicControls) {
            if #available(iOS 26.0, *) {
                AIMagicControlsView()
                    .environmentObject(appState)
            } else {
                Text("AI Magic features require iOS 26.0 or later")
                    .padding()
            }
        }
        .onChange(of: appState.currentBook?.id) { oldID, newID in
            // Only load book when it actually changes, not on every view appearance
            if let book = appState.currentBook, newID != oldID {
                audioManager.loadBook(book)
            }
        }
        .onAppear {
            // Only load if no book is currently loaded (initial load)
            // Check duration == 0 to determine if no book is loaded
            if let book = appState.currentBook, audioManager.duration == 0 {
                audioManager.loadBook(book)
            }
        }
    }
    
    // MARK: - Error Section
    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
    
    private var emptyPlayerView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all, edges: .all)
            
            VStack(spacing: 20) {
                Image(systemName: "play.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("No Book Selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select a book from your library to start playing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Cover Art Section
    private func coverArtSection(availableWidth: CGFloat) -> some View {
        VStack {
            let coverSize = min(280, availableWidth - 32) // Account for padding
            let coverURL = appState.currentBook?.coverImageURL
            
            // Try to load the image - this will re-evaluate whenever currentBook or coverImageURL changes
            if let url = coverURL,
               FileManager.default.fileExists(atPath: url.path),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: coverSize, maxHeight: coverSize)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .id(url.path) // Force re-render when URL changes
            } else {
                // Placeholder with searching indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: coverSize, height: coverSize)
                        .shadow(radius: 10)
                    
                    if coverManager.isSearching && coverManager.searchingBookID == appState.currentBook?.id {
                        // Searching indicator
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Searching for cover...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                    }
                }
                .id(coverURL?.path ?? "no-cover") // Force re-render when cover URL changes
            }
        }
        .padding(.top, 20)
        .onChange(of: appState.currentBook?.coverImageURL) { oldURL, newURL in
            // Force view refresh when coverImageURL changes
            // This ensures the image appears immediately when it's set
        }
    }
    
    // MARK: - Book Info Section
    private var bookInfoSection: some View {
        VStack(spacing: 8) {
            Text(appState.currentBook?.title ?? "No Book Selected")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            
            if let author = appState.currentBook?.author {
                Text(author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            if let currentChapter = audioManager.chapters[safe: audioManager.currentChapterIndex] {
                Text(currentChapter.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { audioManager.currentTime },
                    set: { audioManager.seek(to: $0) }
                ),
                in: 0...max(audioManager.duration, 1)
            )
            .accentColor(.blue)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Time Display Section
    private var timeDisplaySection: some View {
        HStack {
            Text(formatTime(audioManager.currentTime))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(formatTime(audioManager.duration))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Control Buttons Section
    private func controlButtonsSection(availableWidth: CGFloat) -> some View {
        let isCompact = availableWidth < 600 // iPhone vs iPad threshold
        
        if isCompact {
            // iPhone: Only main playback controls
            return AnyView(
                HStack(spacing: 12) {
                    // Previous Chapter
                    Button(action: {
                        audioManager.previousChapter()
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.title3)
                            .foregroundColor(audioManager.chapters.isEmpty ? .gray : .primary)
                    }
                    .disabled(audioManager.chapters.isEmpty)
                    
                    // Skip Backward
                    Button(action: {
                        audioManager.skipBackward(interval: appState.playbackSettings.skipBackwardInterval)
                    }) {
                        Image(systemName: "gobackward.30")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    
                    // Play/Pause
                    Button(action: {
                        if audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            audioManager.play()
                        }
                    }) {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.blue)
                    }
                    
                    // Skip Forward
                    Button(action: {
                        audioManager.skipForward(interval: appState.playbackSettings.skipForwardInterval)
                    }) {
                        Image(systemName: "goforward.30")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    
                    // Next Chapter
                    Button(action: {
                        audioManager.nextChapter()
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.title3)
                            .foregroundColor(audioManager.chapters.isEmpty ? .gray : .primary)
                    }
                    .disabled(audioManager.chapters.isEmpty)
                }
                .padding(.horizontal)
            )
        } else {
            // iPad: Single row with all controls
            return AnyView(
                HStack(spacing: 16) {
                    // Playback Speed Button
                    speedButton
                    
                    // AI Magic Button
                    aiMagicButton
                    
                    Spacer()
                    
                    // Previous Chapter
                    Button(action: {
                        audioManager.previousChapter()
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                            .foregroundColor(audioManager.chapters.isEmpty ? .gray : .primary)
                    }
                    .disabled(audioManager.chapters.isEmpty)
                    
                    // Skip Backward
                    Button(action: {
                        audioManager.skipBackward(interval: appState.playbackSettings.skipBackwardInterval)
                    }) {
                        Image(systemName: "gobackward.30")
                            .font(.title)
                            .foregroundColor(.primary)
                    }
                    
                    // Play/Pause
                    Button(action: {
                        if audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            audioManager.play()
                        }
                    }) {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)
                    }
                    
                    // Skip Forward
                    Button(action: {
                        audioManager.skipForward(interval: appState.playbackSettings.skipForwardInterval)
                    }) {
                        Image(systemName: "goforward.30")
                            .font(.title)
                            .foregroundColor(.primary)
                    }
                    
                    // Next Chapter
                    Button(action: {
                        audioManager.nextChapter()
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                            .foregroundColor(audioManager.chapters.isEmpty ? .gray : .primary)
                    }
                    .disabled(audioManager.chapters.isEmpty)
                    
                    Spacer()
                    
                    // Sleep Timer Button
                    sleepTimerButton
                }
                .padding(.horizontal)
            )
        }
    }
    
    // MARK: - Helper Button Views
    private var speedButton: some View {
        Button(action: {
            showSpeedPicker = true
        }) {
            Text(String(format: "%.2fx", audioManager.playbackSpeed))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .confirmationDialog("Playback Speed", isPresented: $showSpeedPicker, titleVisibility: .visible) {
            Button("0.5x") { audioManager.setPlaybackSpeed(0.5) }
            Button("0.75x") { audioManager.setPlaybackSpeed(0.75) }
            Button("1x") { audioManager.setPlaybackSpeed(1.0) }
            Button("1.25x") { audioManager.setPlaybackSpeed(1.25) }
            Button("1.5x") { audioManager.setPlaybackSpeed(1.5) }
            Button("1.75x") { audioManager.setPlaybackSpeed(1.75) }
            Button("2x") { audioManager.setPlaybackSpeed(2.0) }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private var sleepTimerButton: some View {
        Button(action: {
            if audioManager.isSleepTimerActive {
                audioManager.cancelSleepTimer()
            } else {
                showSleepTimerPicker = true
            }
        }) {
            Image(systemName: audioManager.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(audioManager.isSleepTimerActive ? .blue : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(audioManager.isSleepTimerActive ? Color.blue.opacity(0.1) : Color(.systemGray6))
                .cornerRadius(8)
        }
        .confirmationDialog("Sleep Timer", isPresented: $showSleepTimerPicker, titleVisibility: .visible) {
            Button("15 minutes") { audioManager.startSleepTimer(duration: 15 * 60) }
            Button("30 minutes") { audioManager.startSleepTimer(duration: 30 * 60) }
            Button("45 minutes") { audioManager.startSleepTimer(duration: 45 * 60) }
            Button("60 minutes") { audioManager.startSleepTimer(duration: 60 * 60) }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private var aiMagicButton: some View {
        Button(action: {
            showAIMagicControls = true
        }) {
            Text("✨")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
    
    // MARK: - Chapter Navigation Section
    private func chapterNavigationSection(availableWidth: CGFloat) -> some View {
        let isCompact = availableWidth < 600 // iPhone vs iPad threshold
        
        return VStack(spacing: 12) {
            if !audioManager.chapters.isEmpty {
                HStack {
                    Text("Chapters")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // On iPhone, show Speed, Sleep Timer, and AI Magic buttons here
                    if isCompact {
                        HStack(spacing: 8) {
                            speedButton
                            sleepTimerButton
                            aiMagicButton
                        }
                    }
                }
                .padding(.horizontal)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(audioManager.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(action: {
                                audioManager.seek(to: chapter.startTime)
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
                                    
                                    if index == audioManager.currentChapterIndex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
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
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
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
    
    private func formatTimerTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Array Safe Subscript Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

