import AVFoundation
import Combine
import Foundation

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
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var playerWithObserver: AVPlayer? // Track which player has the observer
    private var sleepTimerTask: Task<Void, Never>?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var currentBookURL: URL? // Track current book URL for security-scoped access
    private var hasSecurityAccess: Bool = false // Track if we started security-scoped access
    private var isPlayerReady: Bool = false // Track if player is ready to play
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Load Book
    func loadBook(_ book: Book) {
        // Clear any previous errors
        playbackError = nil
        
        // Remove time observer before creating new player
        removeTimeObserver()
        stop()
        
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
            let booksDir = BookFileManager.shared.getBooksDirectory()
            let fileName = book.fileURL.lastPathComponent
            
            // Recursively search for the file
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
            
            if let foundURL = searchForFile(in: booksDir, fileName: fileName) {
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
                        self.player?.seek(to: time, completionHandler: { _ in
                            // Seek completed
                        })
                    }
                    
                    // Load duration and parse chapters
                    Task {
                        await self.loadDurationAndChapters(for: item)
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
        // For now, create a single chapter
        // Chapter parsing from M4B metadata will be enhanced later
        // M4B chapter metadata parsing requires more complex async handling
        
        var parsedChapters: [Chapter] = []
        
        // Create a single chapter for the entire book
        // This will be replaced with proper chapter parsing later
        parsedChapters.append(Chapter(
            title: "Chapter 1",
            startTime: 0,
            duration: duration
        ))
        
        // If no chapters were parsed (or only a single placeholder chapter),
        // check if we should simulate chapters
        if parsedChapters.count <= 1 {
            let settings = PersistenceManager.shared.loadSettings()
            if settings.simulateChapters {
                parsedChapters = generateSimulatedChapters(duration: duration, chapterLength: settings.simulatedChapterLength)
            }
        }
        
        self.chapters = parsedChapters
        self.updateCurrentChapterIndex()
    }
    
    // MARK: - Simulated Chapters
    private func generateSimulatedChapters(duration: TimeInterval, chapterLength: TimeInterval) -> [Chapter] {
        guard duration > 0 && chapterLength > 0 else {
            // Fallback to single chapter if invalid duration or chapter length
            return [Chapter(title: "Chapter 1", startTime: 0, duration: duration)]
        }
        
        var chapters: [Chapter] = []
        let numberOfChapters = Int(ceil(duration / chapterLength))
        
        for i in 0..<numberOfChapters {
            let startTime = TimeInterval(i) * chapterLength
            let remainingDuration = duration - startTime
            let chapterDuration = min(chapterLength, remainingDuration)
            
            // Only add chapter if it has positive duration
            if chapterDuration > 0 {
                chapters.append(Chapter(
                    title: "Chapter \(i + 1)",
                    startTime: startTime,
                    duration: chapterDuration
                ))
            }
        }
        
        // Ensure at least one chapter exists
        if chapters.isEmpty {
            chapters.append(Chapter(title: "Chapter 1", startTime: 0, duration: duration))
        }
        
        return chapters
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
    }
    
    func pause() {
        player?.pause()
        // isPlaying will be updated by rate observer
    }
    
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
        cancelSleepTimer() // Cancel sleep timer when stopping
        // Note: Don't remove time observer here - it will be removed when loading a new book
        // Note: Don't reset isPlayerReady here - it will be reset when loading a new book
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let wasPlaying = isPlaying
        
        // Pause during seek to avoid "shaky" playback
        if wasPlaying {
            player.pause()
        }
        
        player.seek(to: cmTime, completionHandler: { [weak self] completed in
            guard let self = self, completed else { return }
            
            DispatchQueue.main.async {
                self.currentTime = time
                self.updateCurrentChapterIndex()
                
                // Resume playback if it was playing before seek
                if wasPlaying && self.isPlayerReady {
                    self.play()
                }
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
        guard currentChapterIndex < chapters.count - 1 else { return }
        let nextChapter = chapters[currentChapterIndex + 1]
        seek(to: nextChapter.startTime)
    }
    
    func previousChapter() {
        guard currentChapterIndex > 0 else {
            // If at first chapter, go to beginning
            seek(to: 0)
            return
        }
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
    }
    
    // MARK: - Sleep Timer
    func startSleepTimer(duration: TimeInterval) {
        // Cancel existing timer if any
        cancelSleepTimer()
        
        sleepTimerRemaining = duration
        sleepTimerInitialDuration = duration
        isSleepTimerActive = true
        
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
                
                // Stop playback when timer reaches 0
                if sleepTimerRemaining <= 0 {
                    pause()
                    isSleepTimerActive = false
                    sleepTimerTask = nil
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
    }
    
    func extendSleepTimer(additionalMinutes: TimeInterval = 600) {
        guard isSleepTimerActive else { return }
        sleepTimerRemaining += additionalMinutes
        sleepTimerInitialDuration += additionalMinutes // Update total duration for tick recalculation
    }
    
    // MARK: - Rate Observer
    private func setupRateObserver() {
        rateObserver?.invalidate()
        
        guard let player = player else { return }
        
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                // Update isPlaying based on actual playback rate
                let wasPlaying = self?.isPlaying ?? false
                let isNowPlaying = player.rate > 0
                
                if wasPlaying != isNowPlaying {
                    self?.isPlaying = isNowPlaying
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
        for (index, chapter) in chapters.enumerated() {
            if currentTime >= chapter.startTime && currentTime < chapter.endTime {
                if currentChapterIndex != index {
                    currentChapterIndex = index
                }
                return
            }
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
    
    deinit {
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

