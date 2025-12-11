import Foundation

// MARK: - Book Model
struct Book: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var author: String?
    var fileURL: URL
    var coverImageURL: URL?
    var duration: TimeInterval
    var currentPosition: TimeInterval
    var dateAdded: Date
    var isDownloaded: Bool
    var googleDriveFileID: String?
    var associatedFiles: [URL] // For cue files and other associated files
    
    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        fileURL: URL,
        coverImageURL: URL? = nil,
        duration: TimeInterval = 0,
        currentPosition: TimeInterval = 0,
        dateAdded: Date = Date(),
        isDownloaded: Bool = false,
        googleDriveFileID: String? = nil,
        associatedFiles: [URL] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.fileURL = fileURL
        self.coverImageURL = coverImageURL
        self.duration = duration
        self.currentPosition = currentPosition
        self.dateAdded = dateAdded
        self.isDownloaded = isDownloaded
        self.googleDriveFileID = googleDriveFileID
        self.associatedFiles = associatedFiles
    }
    
    // Custom Codable implementation for URL encoding
    enum CodingKeys: String, CodingKey {
        case id, title, author, duration, currentPosition, dateAdded
        case isDownloaded, googleDriveFileID
        case fileURLString, coverImageURLString, associatedFilesStrings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        currentPosition = try container.decode(TimeInterval.self, forKey: .currentPosition)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        isDownloaded = try container.decode(Bool.self, forKey: .isDownloaded)
        googleDriveFileID = try container.decodeIfPresent(String.self, forKey: .googleDriveFileID)
        
        let fileURLString = try container.decode(String.self, forKey: .fileURLString)
        fileURL = URL(fileURLWithPath: fileURLString)
        
        if let coverURLString = try container.decodeIfPresent(String.self, forKey: .coverImageURLString) {
            coverImageURL = URL(fileURLWithPath: coverURLString)
        } else {
            coverImageURL = nil
        }
        
        let associatedFilesStrings = try container.decodeIfPresent([String].self, forKey: .associatedFilesStrings) ?? []
        associatedFiles = associatedFilesStrings.map { URL(fileURLWithPath: $0) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(duration, forKey: .duration)
        try container.encode(currentPosition, forKey: .currentPosition)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(isDownloaded, forKey: .isDownloaded)
        try container.encodeIfPresent(googleDriveFileID, forKey: .googleDriveFileID)
        try container.encode(fileURL.path, forKey: .fileURLString)
        try container.encodeIfPresent(coverImageURL?.path, forKey: .coverImageURLString)
        try container.encode(associatedFiles.map { $0.path }, forKey: .associatedFilesStrings)
    }
}

// MARK: - Chapter Model
struct Chapter: Identifiable, Equatable {
    let id: UUID
    let title: String
    let startTime: TimeInterval
    let duration: TimeInterval
    
    var endTime: TimeInterval {
        startTime + duration
    }
    
    init(id: UUID = UUID(), title: String, startTime: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - Playback Settings
struct PlaybackSettings: Codable {
    var playbackSpeed: Double
    var skipForwardInterval: TimeInterval
    var skipBackwardInterval: TimeInterval
    var sleepTimerEnabled: Bool
    var sleepTimerDuration: TimeInterval
    var simulateChapters: Bool
    var simulatedChapterLength: TimeInterval // In seconds
    
    static let `default` = PlaybackSettings(
        playbackSpeed: 1.0,
        skipForwardInterval: 30.0,
        skipBackwardInterval: 30.0,
        sleepTimerEnabled: false,
        sleepTimerDuration: 0,
        simulateChapters: true,
        simulatedChapterLength: 900.0 // 15 minutes default
    )
    
    // Custom initializer to support memberwise initialization
    init(
        playbackSpeed: Double,
        skipForwardInterval: TimeInterval,
        skipBackwardInterval: TimeInterval,
        sleepTimerEnabled: Bool,
        sleepTimerDuration: TimeInterval,
        simulateChapters: Bool,
        simulatedChapterLength: TimeInterval
    ) {
        self.playbackSpeed = playbackSpeed
        self.skipForwardInterval = skipForwardInterval
        self.skipBackwardInterval = skipBackwardInterval
        self.sleepTimerEnabled = sleepTimerEnabled
        self.sleepTimerDuration = sleepTimerDuration
        self.simulateChapters = simulateChapters
        self.simulatedChapterLength = simulatedChapterLength
    }
    
    // Custom Codable implementation for backward compatibility
    enum CodingKeys: String, CodingKey {
        case playbackSpeed
        case skipForwardInterval
        case skipBackwardInterval
        case sleepTimerEnabled
        case sleepTimerDuration
        case simulateChapters
        case simulatedChapterLength
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode existing fields
        playbackSpeed = try container.decode(Double.self, forKey: .playbackSpeed)
        skipForwardInterval = try container.decode(TimeInterval.self, forKey: .skipForwardInterval)
        skipBackwardInterval = try container.decode(TimeInterval.self, forKey: .skipBackwardInterval)
        sleepTimerEnabled = try container.decode(Bool.self, forKey: .sleepTimerEnabled)
        sleepTimerDuration = try container.decode(TimeInterval.self, forKey: .sleepTimerDuration)
        
        // Decode new fields with defaults for backward compatibility
        simulateChapters = try container.decodeIfPresent(Bool.self, forKey: .simulateChapters) ?? true
        simulatedChapterLength = try container.decodeIfPresent(TimeInterval.self, forKey: .simulatedChapterLength) ?? 900.0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playbackSpeed, forKey: .playbackSpeed)
        try container.encode(skipForwardInterval, forKey: .skipForwardInterval)
        try container.encode(skipBackwardInterval, forKey: .skipBackwardInterval)
        try container.encode(sleepTimerEnabled, forKey: .sleepTimerEnabled)
        try container.encode(sleepTimerDuration, forKey: .sleepTimerDuration)
        try container.encode(simulateChapters, forKey: .simulateChapters)
        try container.encode(simulatedChapterLength, forKey: .simulatedChapterLength)
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var books: [Book] = []
    @Published var currentBook: Book?
    @Published var currentChapterIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var playbackSettings: PlaybackSettings = .default
    
    var currentChapters: [Chapter] = []
    
    var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < currentChapters.count else {
            return nil
        }
        return currentChapters[currentChapterIndex]
    }
}

