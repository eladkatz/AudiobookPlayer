import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var chapters: [Chapter] = []
    @Published var currentChapterIndex: Int = 0
    @Published var playbackError: String?
    @Published var playbackSpeed: Double = 1.0
    @Published var sleepTimerRemaining: TimeInterval = 0
    @Published var isSleepTimerActive: Bool = false
    @Published var sleepTimerInitialDuration: TimeInterval = 0 // Total duration for tick calculation
    @Published var showInterruptionToast: Bool = false
    @Published var interruptionToastMessage: String = ""
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var playerWithObserver: AVPlayer? // Track which player has the observer
    private var sleepTimerTask: Task<Void, Never>?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var currentBookURL: URL? // Track current book URL for security-scoped access
    private var currentBookID: UUID? // Track currently loaded book ID to avoid unnecessary reloads
    private var currentBook: Book? // Store current book for Now Playing metadata
    private var hasSecurityAccess: Bool = false // Track if we started security-scoped access
    private var isPlayerReady: Bool = false // Track if player is ready to play
    private var wasPlayingBeforeInterruption: Bool = false // Track playback state before interruption
    private var nowPlayingUpdateTimer: Timer? // Timer to update Now Playing elapsed time
    private var interruptionResumeTask: Task<Void, Never>? // Task to handle delayed resume after interruption
    private var chaptersLoaded: Bool = false // Track if chapters have been loaded for current book
    
    private override init() {
        super.init()
        setupAudioSession()
        setupInterruptionNotifications()
        setupRouteChangeNotifications()
        setupRemoteCommandCenter()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            // Use .playback category with .spokenAudio mode
            // This category will be interrupted by notification sounds by default
            // No special options needed - iOS will handle interruptions automatically
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Interruption Handling
    private func setupInterruptionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    // MARK: - Route Change Handling (for text messages and other audio)
    private func setupRouteChangeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        // Route changes can indicate interruptions, but we'll rely on interruption notifications
        // and the audio session category to handle them properly
    }
    
    private func handleAudioInterruption(reason: String) {
        // Only handle if we're currently playing
        guard isPlaying else { return }
        
        // Cancel any existing resume task
        interruptionResumeTask?.cancel()
        
        // Remember we were playing
        wasPlayingBeforeInterruption = true
        
        // Pause playback
        pause()
        
        // Don't show toast here - it will show when playback resumes
        print("🔇 AudioManager: Audio interrupted by \(reason), paused playback")
        
        // Set up a delayed check to resume when interruption ends
        // This handles cases where the interruption notification might not fire properly (like WhatsApp)
        interruptionResumeTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Wait a bit for the interruption to end (notification sounds are usually short)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if task was cancelled (interruption notification handled it)
            guard !Task.isCancelled else { return }
            
            // If we're still paused and were playing before, check if we should resume
            if !self.isPlaying && self.wasPlayingBeforeInterruption && self.isPlayerReady {
                // Check if interruption has ended (audio session is active again)
                let session = AVAudioSession.sharedInstance()
                if !session.secondaryAudioShouldBeSilencedHint {
                    // Interruption seems to have ended, resume with rewind
                    let settings = PersistenceManager.shared.loadSettings()
                    let rewindAmount = settings.rewindAfterInterruption
                    
                    if rewindAmount > 0 {
                        let newTime = max(0, self.currentTime - rewindAmount)
                        self.seek(to: newTime) { [weak self] in
                            guard let self = self, self.isPlayerReady else { return }
                            self.play()
                            self.showInterruptionToast(message: "Resumed after notification (rewound \(Int(rewindAmount))s)")
                            self.wasPlayingBeforeInterruption = false
                        }
                    } else {
                        self.play()
                        self.showInterruptionToast(message: "Resumed after notification")
                        self.wasPlayingBeforeInterruption = false
                    }
                }
            }
        }
    }
    
    // MARK: - Now Playing Integration
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play/Pause commands
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.pause()
            } else {
                self.play()
            }
            return .success
        }
        
        // Chapter navigation (using next/previous track commands)
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextChapter()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousChapter()
            return .success
        }
        
        // Skip forward/backward (using configured intervals)
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else {
                return .commandFailed
            }
            let settings = PersistenceManager.shared.loadSettings()
            self.skipForward(interval: settings.skipForwardInterval)
            return .success
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else {
                return .commandFailed
            }
            let settings = PersistenceManager.shared.loadSettings()
            self.skipBackward(interval: settings.skipBackwardInterval)
            return .success
        }
        
        // Set skip intervals from settings (will be updated when settings change)
        updateSkipIntervals()
        
        // Seek/scrub support
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: event.positionTime)
            return .success
        }
        
        // Playback speed control
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            self.setPlaybackSpeed(Double(event.playbackRate))
            return .success
        }
        
        // Disable commands not relevant for audiobooks
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
    }
    
    private func updateNowPlayingInfo() {
        guard let book = currentBook else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [:]
        
        // Format title with sleep timer info if active
        var displayTitle = book.title
        if isSleepTimerActive && sleepTimerRemaining > 0 {
            let timerString = formatTimerTime(sleepTimerRemaining)
            displayTitle = "\(book.title) (⏰ \(timerString))"
        }
        
        // Basic metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = displayTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = book.author ?? "Unknown Author"
        nowPlayingInfo[MPMediaItemPropertyGenre] = "Audiobook"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
        
        // Note: Chapter information properties (MPMediaItemPropertyChapterNumber, MPMediaItemPropertyChapterCount)
        // are not available in the MediaPlayer framework for Now Playing info
        
        // Artwork
        if let coverURL = book.coverImageURL,
           FileManager.default.fileExists(atPath: coverURL.path),
           let image = UIImage(contentsOfFile: coverURL.path) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                return image
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        } else {
            // Try covers directory
            let coversDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Covers")
            let coverURL = coversDir.appendingPathComponent("\(book.id.uuidString).jpg")
            if FileManager.default.fileExists(atPath: coverURL.path),
               let image = UIImage(contentsOfFile: coverURL.path) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                    return image
                }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func startNowPlayingUpdates() {
        stopNowPlayingUpdates()
        nowPlayingUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }
    
    private func stopNowPlayingUpdates() {
        nowPlayingUpdateTimer?.invalidate()
        nowPlayingUpdateTimer = nil
    }
    
    private func updateSkipIntervals() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let settings = PersistenceManager.shared.loadSettings()
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: settings.skipForwardInterval)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: settings.skipBackwardInterval)]
    }
    
    // MARK: - Helper Methods
    private func formatTimerTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption started - pause playback and remember state
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                pause()
                print("🔇 AudioManager: Interruption began, paused playback")
            }
            
        case .ended:
            // Cancel any delayed resume task since the interruption notification handled it
            interruptionResumeTask?.cancel()
            interruptionResumeTask = nil
            
            // Interruption ended - check if we should resume
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                wasPlayingBeforeInterruption = false
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) && wasPlayingBeforeInterruption && isPlayerReady {
                // Get rewind amount from settings
                let settings = PersistenceManager.shared.loadSettings()
                let rewindAmount = settings.rewindAfterInterruption
                
                if rewindAmount > 0 {
                    // Rewind by configured amount
                    let newTime = max(0, currentTime - rewindAmount)
                    seek(to: newTime) { [weak self] in
                        // Resume after seek completes
                        guard let self = self, self.isPlayerReady else { return }
                        self.play()
                        // Show toast notification when resuming after rewind
                        self.showInterruptionToast(message: "Resumed after interruption (rewound \(Int(rewindAmount))s)")
                        print("▶️ AudioManager: Interruption ended, rewound \(rewindAmount)s and resumed playback")
                    }
                } else {
                    // No rewind, just resume
                    play()
                    // Show toast notification when resuming (no rewind)
                    showInterruptionToast(message: "Resumed after interruption")
                    print("▶️ AudioManager: Interruption ended, resumed playback (no rewind)")
                }
            }
            
            wasPlayingBeforeInterruption = false
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Toast Notification
    private func showInterruptionToast(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.interruptionToastMessage = message
            self.showInterruptionToast = true
            
            // Get rewind amount from settings to determine toast duration
            let settings = PersistenceManager.shared.loadSettings()
            let rewindAmount = max(settings.rewindAfterInterruption, 1.0) // At least 1 second
            
            // Hide toast after rewind duration
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(rewindAmount * 1_000_000_000))
                self.showInterruptionToast = false
            }
        }
    }
    
    // MARK: - Load Book
    func loadBook(_ book: Book) {
        let loadStart = Date()
        print("⏱️ [Performance] AudioManager.loadBook START for '\(book.title)'")
        // If this book is already loaded, don't reload it
        if currentBookID == book.id && player != nil {
            return
        }
        
        // Clear any previous errors
        playbackError = nil
        
        // Remove time observer before creating new player
        removeTimeObserver()
        wasPlayingBeforeInterruption = false // Reset interruption state when loading new book
        stop()
        
        // Track the current book ID and store book reference
        currentBookID = book.id
        currentBook = book
        chaptersLoaded = false // Reset chapters loaded flag when loading new book
        
        // Remove previous observers
        statusObserver?.invalidate()
        statusObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil
        isPlayerReady = false
        
        // Check if file exists - try both path and resolving symlinks
        let filePath = book.fileURL.path
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: filePath)) ?? filePath
        
        // Determine the actual file URL to use
        var actualURL: URL
        
        if FileManager.default.fileExists(atPath: filePath) {
            actualURL = book.fileURL
        } else if FileManager.default.fileExists(atPath: resolvedPath) {
            actualURL = URL(fileURLWithPath: resolvedPath)
        } else {
            // Try to find the file in the Books directory (including subdirectories) by filename
            // This search can be slow for large directories, but file is usually found immediately
            let booksDir = BookFileManager.shared.getBooksDirectory()
            let fileName = book.fileURL.lastPathComponent
            
            // Recursively search for the file (synchronous but usually fast)
            func searchForFile(in directory: URL, fileName: String) -> URL? {
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return nil
                }
                
                for case let fileURL as URL in enumerator {
                    let file = fileURL.lastPathComponent
                    if file.lowercased() == fileName.lowercased() ||
                       file.removingPercentEncoding?.lowercased() == fileName.removingPercentEncoding?.lowercased() {
                        return fileURL
                    }
                }
                return nil
            }
            
            let searchStart = Date()
            if let foundURL = searchForFile(in: booksDir, fileName: fileName) {
                let searchElapsed = Date().timeIntervalSince(searchStart)
                if searchElapsed > 0.1 {
                    print("⏱️ [Performance] File search took \(String(format: "%.3f", searchElapsed))s")
                }
                actualURL = foundURL
                print("✅ AudioManager: Found file at: \(foundURL.path)")
            } else {
                playbackError = "File not found. Please re-import the book."
                print("⚠️ AudioManager: File not found for book '\(book.title)' - searched in: \(booksDir.path)")
                return
            }
        }
        
        // Stop previous security-scoped access if any
        if hasSecurityAccess, let previousURL = currentBookURL {
            previousURL.stopAccessingSecurityScopedResource()
            hasSecurityAccess = false
        }
        
        // Only use security-scoped access if file is outside app sandbox
        let needsSecurityAccess = !actualURL.path.contains("/Documents/")
        if needsSecurityAccess {
            guard actualURL.startAccessingSecurityScopedResource() else {
                playbackError = "Cannot access file. Please re-import the book."
                print("Failed to access security-scoped resource: \(actualURL)")
                return
            }
            hasSecurityAccess = true
            currentBookURL = actualURL
        } else {
            hasSecurityAccess = false
            currentBookURL = nil
        }
        
        // Create player item using the actual URL
        let newPlayerItem = AVPlayerItem(url: actualURL)
        playerItem = newPlayerItem
        player = AVPlayer(playerItem: newPlayerItem)
        
        // Observe player item status
        statusObserver = newPlayerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.playbackError = nil
                    self.isPlayerReady = true
                    
                    // Set initial position once ready (wait for seek to complete)
                    if book.currentPosition > 0 {
                        let time = CMTime(seconds: book.currentPosition, preferredTimescale: 600)
                        let savedPosition = book.currentPosition
                        self.player?.seek(to: time, completionHandler: { [weak self] completed in
                            guard let self = self, completed else { return }
                            // Seek completed - chapter change will trigger transcription check
                            DispatchQueue.main.async {
                                self.currentTime = savedPosition
                                self.updateCurrentChapterIndex()
                            }
                        })
                    } else {
                        // Even at position 0, chapter change will trigger transcription check
                        DispatchQueue.main.async {
                            self.updateCurrentChapterIndex()
                        }
                    }
                    
                    // Load duration and parse chapters
                    Task {
                        let durationStart = Date()
                        print("⏱️ [Performance] loadDurationAndChapters START")
                        await self.loadDurationAndChapters(for: item)
                        let durationElapsed = Date().timeIntervalSince(durationStart)
                        print("⏱️ [Performance] loadDurationAndChapters END - elapsed: \(String(format: "%.3f", durationElapsed))s")
                    }
                    
                    // Observe player rate to sync isPlaying state
                    self.setupRateObserver()
                case .failed:
                    let error = item.error?.localizedDescription ?? "Unknown error"
                    self.playbackError = "Playback failed: \(error)"
                    self.isPlayerReady = false
                    self.isPlaying = false
                    print("Player item failed: \(error)")
                    if self.hasSecurityAccess, let url = self.currentBookURL {
                        url.stopAccessingSecurityScopedResource()
                        self.hasSecurityAccess = false
                        self.currentBookURL = nil
                    }
                case .unknown:
                    self.isPlayerReady = false
                    break
                @unknown default:
                    break
                }
            }
        }
        
        // Observe time updates
        setupTimeObserver()
        
        // Load playback speed from settings
        let settings = PersistenceManager.shared.loadSettings()
        setPlaybackSpeed(settings.playbackSpeed)
        
        // Update Now Playing info
        updateNowPlayingInfo()
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: newPlayerItem
        )
        
        // Observe errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailed),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: newPlayerItem
        )
        
        let loadElapsed = Date().timeIntervalSince(loadStart)
        print("⏱️ [Performance] AudioManager.loadBook END (synchronous part) - elapsed: \(String(format: "%.3f", loadElapsed))s")
    }
    
    private func loadDurationAndChapters(for item: AVPlayerItem) async {
        do {
            let duration = try await item.asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite {
                await MainActor.run {
                    self.duration = durationSeconds
                    // Parse chapters after duration is loaded
                    self.parseChapters(from: item.asset, duration: durationSeconds)
                }
            }
        } catch {
            await MainActor.run {
                self.playbackError = "Failed to load duration: \(error.localizedDescription)"
            }
            print("Failed to load duration: \(error)")
        }
    }
    
    // MARK: - Chapter Parsing
    private func parseChapters(from asset: AVAsset, duration: TimeInterval) {
        // Use shared chapter parser with deterministic IDs
        guard let book = currentBook else {
            self.chapters = []
            return
        }
        let parsedChapters = ChapterParser.shared.parseChapters(from: asset, duration: duration, bookID: book.id)
        
        self.chapters = parsedChapters
        self.chaptersLoaded = true // Mark chapters as loaded
        self.updateCurrentChapterIndex()
        self.updateNowPlayingInfo() // Update Now Playing with chapter info
        
        // Now that chapters are loaded, trigger transcription check if needed
        if #available(iOS 26.0, *) {
            ensureCurrentChapterTranscribed()
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        guard isPlayerReady, let player = player else {
            return
        }
        
        // Ensure playback speed is set
        player.rate = Float(playbackSpeed)
        player.play()
        // isPlaying will be updated by rate observer
        startNowPlayingUpdates()
        updateNowPlayingInfo()
        
        // Trigger transcription check when playback starts (if chapters are loaded)
        // This handles the case where user switches books and hits play without chapter change
        if chaptersLoaded {
            if #available(iOS 26.0, *) {
                ensureCurrentChapterTranscribed()
            }
        }
    }
    
    func pause() {
        player?.pause()
        // isPlaying will be updated by rate observer
        updateNowPlayingInfo()
    }
    
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
        wasPlayingBeforeInterruption = false // Reset interruption state
        cancelSleepTimer() // Cancel sleep timer when stopping
        currentBookID = nil // Clear current book ID when stopping
        currentBook = nil // Clear current book reference
        stopNowPlayingUpdates()
        interruptionResumeTask?.cancel()
        interruptionResumeTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Note: Don't remove time observer here - it will be removed when loading a new book
        // Note: Don't reset isPlayerReady here - it will be reset when loading a new book
    }
    
    func seek(to time: TimeInterval, completion: (() -> Void)? = nil) {
        guard let player = player else {
            completion?()
            return
        }
        
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let seekTimeFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        let seekMsg = "🎯 [AudioManager] USER SEEKED to location: \(seekTimeFormatted) (\(time)s)"
        print(seekMsg)
        FileLogger.shared.log(seekMsg, category: "AudioManager")
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let wasPlaying = isPlaying
        
        // Pause during seek to avoid "shaky" playback
        if wasPlaying {
            player.pause()
        }
        
        player.seek(to: cmTime, completionHandler: { [weak self] completed in
            guard let self = self, completed else {
                let seekErrorMsg = "⚠️ [AudioManager] Seek completed with error or was cancelled"
                print(seekErrorMsg)
                FileLogger.shared.log(seekErrorMsg, category: "AudioManager")
                completion?()
                return
            }
            
            DispatchQueue.main.async {
                self.currentTime = time
                self.updateCurrentChapterIndex()
                self.updateNowPlayingInfo() // Update Now Playing after seek
                
                let seekSuccessMsg = "✅ [AudioManager] Seek completed successfully to \(seekTimeFormatted)"
                print(seekSuccessMsg)
                FileLogger.shared.log(seekSuccessMsg, category: "AudioManager")
                
                // Resume playback if it was playing before seek
                if wasPlaying && self.isPlayerReady {
                    self.play()
                }
                
                // Chapter change detection will trigger transcription check
                
                completion?()
            }
        })
    }
    
    func skipForward(interval: TimeInterval) {
        let newTime = min(currentTime + interval, duration)
        seek(to: newTime)
    }
    
    func skipBackward(interval: TimeInterval) {
        let newTime = max(currentTime - interval, 0)
        seek(to: newTime)
    }
    
    // MARK: - Chapter Navigation
    func nextChapter() {
        guard !chapters.isEmpty,
              currentChapterIndex >= 0,
              currentChapterIndex < chapters.count - 1 else { return }
        let nextChapter = chapters[currentChapterIndex + 1]
        seek(to: nextChapter.startTime)
    }
    
    func previousChapter() {
        guard !chapters.isEmpty else {
            seek(to: 0)
            return
        }
        guard currentChapterIndex > 0 else {
            // If at first chapter, go to beginning
            seek(to: 0)
            return
        }
        guard currentChapterIndex < chapters.count else { return }
        let previousChapter = chapters[currentChapterIndex - 1]
        seek(to: previousChapter.startTime)
    }
    
    // MARK: - Playback Speed
    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        // Update settings
        var settings = PersistenceManager.shared.loadSettings()
        settings.playbackSpeed = speed
        PersistenceManager.shared.saveSettings(settings)
        // Only set rate if currently playing
        if isPlaying, let player = player {
            player.rate = Float(speed)
        }
        updateNowPlayingInfo() // Update Now Playing with new speed
    }
    
    // MARK: - Sleep Timer
    func startSleepTimer(duration: TimeInterval) {
        // Cancel existing timer if any
        cancelSleepTimer()
        
        sleepTimerRemaining = duration
        sleepTimerInitialDuration = duration
        isSleepTimerActive = true
        updateNowPlayingInfo() // Update Now Playing with sleep timer info
        
        // Start countdown task
        sleepTimerTask = Task { @MainActor in
            while sleepTimerRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Check if task was cancelled
                if Task.isCancelled {
                    break
                }
                
                // Check if timer is still active (might have been cancelled)
                guard isSleepTimerActive else {
                    break
                }
                
                sleepTimerRemaining -= 1
                updateNowPlayingInfo() // Update Now Playing every second with remaining time
                
                // Stop playback when timer reaches 0
                if sleepTimerRemaining <= 0 {
                    pause()
                    isSleepTimerActive = false
                    sleepTimerTask = nil
                    updateNowPlayingInfo() // Update Now Playing to remove timer info
                    break
                }
            }
        }
    }
    
    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        isSleepTimerActive = false
        sleepTimerRemaining = 0
        sleepTimerInitialDuration = 0
        updateNowPlayingInfo() // Update Now Playing to remove timer info
    }
    
    func extendSleepTimer(additionalMinutes: TimeInterval = 600) {
        guard isSleepTimerActive else { return }
        sleepTimerRemaining += additionalMinutes
        sleepTimerInitialDuration += additionalMinutes // Update total duration for tick recalculation
        updateNowPlayingInfo() // Update Now Playing with new timer duration
    }
    
    // MARK: - Rate Observer
    private func setupRateObserver() {
        rateObserver?.invalidate()
        
        guard let player = player else { return }
        
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Update isPlaying based on actual playback rate
                let wasPlaying = self.isPlaying
                let isNowPlaying = player.rate > 0
                
                if wasPlaying != isNowPlaying {
                    self.isPlaying = isNowPlaying
                    self.updateNowPlayingInfo() // Update Now Playing when playback state changes
                    
                    // Start/stop update timer based on playback state
                    if isNowPlaying {
                        self.startNowPlayingUpdates()
                    } else {
                        self.stopNowPlayingUpdates()
                    }
                }
            }
        }
    }
    
    // MARK: - Time Observer
    private func setupTimeObserver() {
        removeTimeObserver()
        
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.updateCurrentChapterIndex()
        }
        
        // Store reference to the player that has this observer
        playerWithObserver = player
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver, let player = playerWithObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
            playerWithObserver = nil
        }
    }
    
    // MARK: - Chapter Index Update
    private func updateCurrentChapterIndex() {
        // Guard against empty chapters
        guard !chapters.isEmpty else {
            currentChapterIndex = -1
            return
        }
        
        for (index, chapter) in chapters.enumerated() {
            if currentTime >= chapter.startTime && currentTime < chapter.endTime {
                if currentChapterIndex != index {
                    currentChapterIndex = index
                    updateNowPlayingInfo() // Update Now Playing when chapter changes
                    
                    // Trigger transcription check when chapter changes (only if chapters are loaded)
                    if chaptersLoaded {
                        if #available(iOS 26.0, *) {
                            ensureCurrentChapterTranscribed()
                        }
                    }
                }
                return
            }
        }
        
        // If no chapter found, set to -1 or last chapter if past end
        if let lastChapter = chapters.last, currentTime >= lastChapter.endTime {
            let lastIndex = chapters.count - 1
            if currentChapterIndex != lastIndex {
                currentChapterIndex = lastIndex
                updateNowPlayingInfo()
                
                // Trigger transcription check when chapter changes (only if chapters are loaded)
                if chaptersLoaded {
                    if #available(iOS 26.0, *) {
                        ensureCurrentChapterTranscribed()
                    }
                }
            }
        } else {
            currentChapterIndex = -1
        }
    }
    
    // MARK: - Notifications
    @objc private func playerDidFinishPlaying() {
        isPlaying = false
    }
    
    @objc private func playerItemFailed(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            playbackError = "Playback failed: \(error.localizedDescription)"
            print("Player item failed to play: \(error)")
        }
    }
    
    // MARK: - Chapter-Based Transcription
    
    private var chapterTranscriptionTask: Task<Void, Never>?
    
    @available(iOS 26.0, *)
    func ensureCurrentChapterTranscribed() {
        // Cancel previous task
        chapterTranscriptionTask?.cancel()
        
        guard let book = currentBook,
              !chapters.isEmpty,
              currentChapterIndex >= 0,
              currentChapterIndex < chapters.count else {
            let debugMsg = "🔍 [AudioManager] ensureCurrentChapterTranscribed: Skipping - book=\(currentBook != nil ? "exists" : "nil"), chapters.count=\(chapters.count), currentChapterIndex=\(currentChapterIndex)"
            print(debugMsg)
            FileLogger.shared.log(debugMsg, category: "AudioManager")
            return
        }
        
        let chapterIndex = currentChapterIndex
        let chapter = chapters[chapterIndex]
        
        let startMsg = "🔍 [AudioManager] ensureCurrentChapterTranscribed: Starting for book='\(book.title)', chapter='\(chapter.title)', chapterIndex=\(chapterIndex)"
        print(startMsg)
        FileLogger.shared.log(startMsg, category: "AudioManager")
        
        // Check if already transcribed (async check with 500ms settle delay)
        chapterTranscriptionTask = Task.detached(priority: .userInitiated) {
            let chapterIndex = await MainActor.run { self.currentChapterIndex }
            
            // Check if transcription is enabled
            guard TranscriptionSettings.shared.isEnabled else {
                let disabledMsg = "🚫 [AudioManager] ensureCurrentChapterTranscribed: Transcription is disabled - skipping chapterIndex=\(chapterIndex)"
                print(disabledMsg)
                FileLogger.shared.log(disabledMsg, category: "AudioManager")
                return
            }
            
            // Check if SpeechTranscriber is available
            guard await TranscriptionManager.shared.isTranscriberAvailable() else {
                let unavailableMsg = "🚫 [AudioManager] ensureCurrentChapterTranscribed: SpeechTranscriber is not available - skipping chapterIndex=\(chapterIndex)"
                print(unavailableMsg)
                FileLogger.shared.log(unavailableMsg, category: "AudioManager")
                return
            }
            
            // Check if already transcribed
            let isTranscribed = await TranscriptionDatabase.shared.isChapterTranscribed(
                bookID: book.id,
                chapterIndex: chapterIndex
            )
            
            if isTranscribed {
                let alreadyDoneMsg = "✅ [AudioManager] ensureCurrentChapterTranscribed: Chapter already transcribed - chapterIndex=\(chapterIndex)"
                print(alreadyDoneMsg)
                FileLogger.shared.log(alreadyDoneMsg, category: "AudioManager")
                
                // Even though this chapter is already transcribed, we should still queue the next chapter
                await self.queueNextChapterIfNeeded(book: book, currentChapterIndex: chapterIndex)
                
                return // Already done
            }
            
            let needsTranscriptionMsg = "⏳ [AudioManager] ensureCurrentChapterTranscribed: Chapter needs transcription - waiting 500ms settle delay - chapterIndex=\(chapterIndex)"
            print(needsTranscriptionMsg)
            FileLogger.shared.log(needsTranscriptionMsg, category: "AudioManager")
            
            // Wait 500ms to see if user settles on this chapter
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Check if still on same chapter
            guard !Task.isCancelled else {
                let cancelledMsg = "🚫 [AudioManager] ensureCurrentChapterTranscribed: Task cancelled during settle delay - chapterIndex=\(chapterIndex)"
                print(cancelledMsg)
                FileLogger.shared.log(cancelledMsg, category: "AudioManager")
                return
            }
            
            // Verify still on same chapter index
            let stillOnSameChapter = await MainActor.run {
                guard self.currentChapterIndex >= 0,
                      self.currentChapterIndex < self.chapters.count else {
                    return false
                }
                return self.currentChapterIndex == chapterIndex
            }
            
            if !stillOnSameChapter {
                // User moved to different chapter
                let movedMsg = "🚫 [AudioManager] ensureCurrentChapterTranscribed: User moved to different chapter - was index \(chapterIndex), now \(await MainActor.run { self.currentChapterIndex })"
                print(movedMsg)
                FileLogger.shared.log(movedMsg, category: "AudioManager")
                return // User moved to different chapter
            }
            
            // Check again if transcribed (might have been transcribed while waiting)
            let isStillTranscribed = await TranscriptionDatabase.shared.isChapterTranscribed(
                bookID: book.id,
                chapterIndex: chapterIndex
            )
            let stillNeedsTranscription = !isStillTranscribed
            
            if stillNeedsTranscription {
                // Get chapter info for logging
                let chapterInfo: (title: String, startTime: TimeInterval, endTime: TimeInterval)? = await MainActor.run {
                    guard chapterIndex >= 0 && chapterIndex < self.chapters.count else {
                        return nil
                    }
                    let chapter = self.chapters[chapterIndex]
                    return (chapter.title, chapter.startTime, chapter.endTime)
                }
                
                guard let info = chapterInfo else {
                    let invalidMsg = "🚫 [AudioManager] ensureCurrentChapterTranscribed: Chapter validation failed - chapterIndex=\(chapterIndex)"
                    print(invalidMsg)
                    FileLogger.shared.log(invalidMsg, category: "AudioManager")
                    return
                }
                
                let enqueueMsg = "🚀 [AudioManager] ensureCurrentChapterTranscribed: Enqueuing transcription - book='\(book.title)', chapter='\(info.title)', chapterIndex=\(chapterIndex)"
                print(enqueueMsg)
                FileLogger.shared.log(enqueueMsg, category: "AudioManager")
                
                // Enqueue transcription
                await TranscriptionQueue.shared.enqueueChapter(
                    book: book,
                    chapterIndex: chapterIndex,
                    startTime: info.startTime,
                    endTime: info.endTime,
                    priority: .high
                )
                
                // Queue next chapter if it exists and isn't transcribed
                await self.queueNextChapterIfNeeded(book: book, currentChapterIndex: chapterIndex)
            } else {
                let transcribedWhileWaitingMsg = "✅ [AudioManager] ensureCurrentChapterTranscribed: Chapter was transcribed while waiting - chapterIndex=\(chapterIndex)"
                print(transcribedWhileWaitingMsg)
                FileLogger.shared.log(transcribedWhileWaitingMsg, category: "AudioManager")
            }
        }
    }
    
    // MARK: - Next Chapter Pre-transcription
    
    @available(iOS 26.0, *)
    private func queueNextChapterIfNeeded(book: Book, currentChapterIndex: Int) async {
        // Get next chapter index
        let nextChapterIndex: Int? = await MainActor.run {
            guard currentChapterIndex >= 0,
                  currentChapterIndex < self.chapters.count - 1 else {
                return nil
            }
            return currentChapterIndex + 1
        }
        
        guard let nextIndex = nextChapterIndex,
              nextIndex < chapters.count else {
            // No next chapter (last chapter or invalid index)
            return
        }
        
        let nextChapterInfo: (title: String, startTime: TimeInterval, endTime: TimeInterval)? = await MainActor.run {
            guard nextIndex < self.chapters.count else {
                return nil
            }
            let chapter = self.chapters[nextIndex]
            return (chapter.title, chapter.startTime, chapter.endTime)
        }
        
        guard let nextInfo = nextChapterInfo else {
            return
        }
        
        // Check if already transcribed
        let isTranscribed = await TranscriptionDatabase.shared.isChapterTranscribed(
            bookID: book.id,
            chapterIndex: nextIndex
        )
        
        if isTranscribed {
            let alreadyDoneMsg = "✅ [AudioManager] Next chapter already transcribed, skipping: chapter='\(nextInfo.title)', chapterIndex=\(nextIndex)"
            print(alreadyDoneMsg)
            FileLogger.shared.log(alreadyDoneMsg, category: "AudioManager")
            return
        }
        
        // Check if already queued or running
        let isQueued = await TranscriptionQueue.shared.isChapterQueuedOrRunning(
            bookID: book.id,
            chapterIndex: nextIndex
        )
        
        if isQueued {
            let alreadyQueuedMsg = "⚠️ [AudioManager] Next chapter already queued/running, skipping: chapter='\(nextInfo.title)', chapterIndex=\(nextIndex)"
            print(alreadyQueuedMsg)
            FileLogger.shared.log(alreadyQueuedMsg, category: "AudioManager")
            return
        }
        
        // Queue next chapter with medium priority
        let queueNextMsg = "📋 [AudioManager] Queueing next chapter for pre-transcription: chapter='\(nextInfo.title)', chapterIndex=\(nextIndex)"
        print(queueNextMsg)
        FileLogger.shared.log(queueNextMsg, category: "AudioManager")
        
        await TranscriptionQueue.shared.enqueueNextChapter(
            book: book,
            chapterIndex: nextIndex,
            startTime: nextInfo.startTime,
            endTime: nextInfo.endTime
        )
    }
    
    @available(iOS 26.0, *)
    func checkIncompleteTranscriptions() async {
        guard let book = currentBook,
              !chapters.isEmpty,
              currentChapterIndex >= 0,
              currentChapterIndex < chapters.count else {
            return
        }
        
        let chapter = chapters[currentChapterIndex]
        
        // Check if chapter was marked as transcribing but not complete
        let isTranscribing = await TranscriptionDatabase.shared.isChapterTranscribing(
            bookID: book.id,
            chapterIndex: currentChapterIndex
        )
        
        if isTranscribing {
            // Retry transcription
            ensureCurrentChapterTranscribed()
        }
    }
    
    deinit {
        chapterTranscriptionTask?.cancel()
        cancelSleepTimer()
        removeTimeObserver()
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        // Stop security-scoped access if active
        if hasSecurityAccess, let url = currentBookURL {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

