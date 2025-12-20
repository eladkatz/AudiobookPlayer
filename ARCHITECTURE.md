# Architecture Documentation

This document provides a detailed overview of the AudioBook Player codebase architecture, class structure, and their interactions.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [Data Flow](#data-flow)
4. [Class Details](#class-details)
5. [Interaction Diagrams](#interaction-diagrams)

## Architecture Overview

The app follows a **Model-View-ViewModel (MVVM)** pattern with manager classes handling business logic:

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│  (LibraryView, PlayerView, SettingsView, etc.)          │
└────────────────────┬────────────────────────────────────┘
                     │ Observes
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Observable Managers                    │
│  (AudioManager, GoogleDriveManager, CoverImageManager,   │
│   AppState)                                              │
└────────────────────┬────────────────────────────────────┘
                     │ Uses
                     ▼
┌─────────────────────────────────────────────────────────┐
│                    Data Models                           │
│  (Book, Chapter, PlaybackSettings)                       │
└────────────────────┬────────────────────────────────────┘
                     │ Persisted by
                     ▼
┌─────────────────────────────────────────────────────────┐
│                 PersistenceManager                       │
│              (UserDefaults Storage)                      │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. App Entry Point

#### `AudioBookPlayerApp`
- **Location**: `AudioBookPlayer/AudioBookPlayerApp.swift`
- **Purpose**: Main app entry point, initializes app state
- **Responsibilities**:
  - Creates and manages `AppState` as a `@StateObject`
  - Loads initial data on app launch
  - Sets up Google Drive authentication check
  - Provides `AppState` as environment object to all views

**Key Methods**:
- `loadInitialData()`: Loads books, settings, and current book from persistence
  - Also triggers `CoverImageManager.retryFailedDownloads()` to retry cover downloads for books without covers

### 2. Models

#### `Book`
- **Location**: `AudioBookPlayer/Models/Models.swift`
- **Purpose**: Represents an audiobook
- **Properties**:
  - `id: UUID` - Unique identifier
  - `title: String` - Book title
  - `author: String?` - Optional author name
  - `fileURL: URL` - Path to M4B file
  - `coverImageURL: URL?` - Path to cover image
  - `duration: TimeInterval` - Total duration in seconds
  - `currentPosition: TimeInterval` - Current playback position
  - `dateAdded: Date` - When book was added
  - `isDownloaded: Bool` - Whether file is local
  - `googleDriveFileID: String?` - Google Drive folder ID (if imported from Drive)
  - `associatedFiles: [URL]` - Related files (CUE, NFO, etc.)

**Custom Codable**: Handles URL encoding/decoding for persistence

#### `Chapter`
- **Location**: `AudioBookPlayer/Models/Models.swift`
- **Purpose**: Represents a chapter in an audiobook
- **Properties**:
  - `id: UUID`
  - `title: String`
  - `startTime: TimeInterval`
  - `duration: TimeInterval`
  - `endTime: TimeInterval` (computed)

#### `TranscribedSentence`
- **Location**: `AudioBookPlayer/Models/Models.swift`
- **Purpose**: Represents a single transcribed sentence with timestamps
- **Availability**: iOS 26.0+ only
- **Properties**:
  - `id: UUID`: Unique sentence identifier
  - `bookID: UUID`: Associated book identifier
  - `text: String`: Transcribed sentence text
  - `startTime: TimeInterval`: Absolute start time in book (seconds, rounded to 0.1s)
  - `endTime: TimeInterval`: Absolute end time in book (seconds, rounded to 0.1s)
  - `chunkID: UUID`: Parent transcription chunk identifier
  - `createdAt: Date`: Timestamp when sentence was created
- **Computed Properties**:
  - `srtTimeString: String`: SRT-formatted timestamp string (for display, though not currently shown in UI)

#### `TranscriptionChunk`
- **Location**: `AudioBookPlayer/Models/Models.swift`
- **Purpose**: Represents metadata for a transcription chunk (typically 2-minute segment)
- **Availability**: iOS 26.0+ only
- **Properties**:
  - `id: UUID`: Unique chunk identifier
  - `bookID: UUID`: Associated book identifier
  - `startTime: TimeInterval`: Chunk start time (seconds, rounded to 0.1s)
  - `endTime: TimeInterval`: Chunk end time (seconds, rounded to 0.1s)
  - `createdAt: Date`: Timestamp when chunk was created
  - `isComplete: Bool`: Whether chunk transcription is complete


#### `PlaybackSettings`
- **Location**: `AudioBookPlayer/Models/Models.swift`
- **Purpose**: User playback preferences
- **Properties**:
  - `playbackSpeed: Double` - Playback speed (0.5x - 2.0x), persisted and restored
  - `skipForwardInterval: TimeInterval`
  - `skipBackwardInterval: TimeInterval`
  - `simulateChapters: Bool` - Whether to generate simulated chapters for books without CUE files
  - `simulatedChapterLength: TimeInterval` - Length of simulated chapters in seconds (default: 900 = 15 minutes)
- **Note**: Sleep timer is no longer stored in settings - it's a runtime feature controlled directly from the player
- **Custom Codable**: Implements backward compatibility for new fields using `decodeIfPresent` with defaults

#### `AppState`
- **Location**: `AudioBookPlayer/Models/Models.swift`
- **Purpose**: Global app state (ObservableObject)
- **Properties**:
  - `@Published var books: [Book]` - All books in library
  - `@Published var currentBook: Book?` - Currently playing book
  - `@Published var currentChapterIndex: Int` - Current chapter
  - `@Published var isPlaying: Bool` - Playback state
  - `@Published var currentTime: TimeInterval` - Current playback time
  - `@Published var playbackSettings: PlaybackSettings` - User settings

### 3. Managers

#### `AudioManager`
- **Location**: `AudioBookPlayer/Managers/AudioManager.swift`
- **Type**: Singleton (`ObservableObject`)
- **Purpose**: Manages audio playback using AVFoundation
- **Key Properties**:
  - `@Published var isPlaying: Bool`
  - `@Published var currentTime: TimeInterval`
  - `@Published var duration: TimeInterval`
  - `@Published var chapters: [Chapter]`
  - `@Published var playbackError: String?`
  - `@Published var playbackSpeed: Double` - Current playback speed (0.5x - 2.0x)
  - `@Published var sleepTimerRemaining: TimeInterval` - Remaining time on sleep timer
  - `@Published var isSleepTimerActive: Bool` - Whether sleep timer is running
  - `@Published var sleepTimerInitialDuration: TimeInterval` - Total timer duration for tick calculation

**Key Methods**:
- `loadBook(_ book: Book)`: Loads a book for playback
  - Resolves file paths (handles symlinks, searches subdirectories)
  - Creates `AVPlayerItem` and `AVPlayer`
  - Sets up time observers
  - Handles security-scoped resource access
  - Generates simulated chapters if no CUE file exists and simulation is enabled
  - Loads playback speed from settings
  - Sets up Now Playing info and remote command center
- `play()`: Starts playback
- `pause()`: Pauses playback
- `seek(to time: TimeInterval)`: Seeks to specific time
- `setPlaybackSpeed(_ speed: Double)`: Adjusts playback speed and saves to settings
- `skipForward()` / `skipBackward()`: Skips by configured intervals
- `nextChapter()` / `previousChapter()`: Navigate between chapters
- `generateSimulatedChapters(duration:chapterLength:)`: Creates evenly-spaced chapters based on duration
- `startSleepTimer(duration:)`: Starts sleep timer countdown, pauses playback when expired
- `cancelSleepTimer()`: Cancels active sleep timer
- `extendSleepTimer(additionalMinutes:)`: Adds time to active timer (default: 10 minutes)
- `setupInterruptionNotifications()`: Observes AVAudioSession interruptions
- `handleInterruption(_:)`: Handles audio interruptions (pauses, remembers state, resumes with rewind)
- `setupRemoteCommandCenter()`: Configures Lock Screen/Control Center controls
- `updateNowPlayingInfo()`: Updates Now Playing metadata with current playback state

**Internal State**:
- `player: AVPlayer?` - AVFoundation player instance
- `playerItem: AVPlayerItem?` - Current player item
- `timeObserver: Any?` - Time update observer
- `isPlayerReady: Bool` - Whether player is ready to play
- `sleepTimerTask: Task<Void, Never>?` - Async task for timer countdown

#### `GoogleDriveManager`
- **Location**: `AudioBookPlayer/Managers/GoogleDriveManager.swift`
- **Type**: Singleton (`ObservableObject`)
- **Purpose**: Handles Google Drive authentication and file operations
- **Key Properties**:
  - `@Published var isAuthenticated: Bool`
  - `@Published var isDownloading: Bool`
  - `@Published var downloadProgress: Double`
  - `@Published var currentDownloadFile: String`

**Key Methods**:
- `checkAuthenticationStatus()`: Checks if user is already signed in, restores from keychain on physical devices
- `signIn(presentingViewController:)`: Signs in with Google
- `signOut()`: Signs out
- `listFiles(in folderID:)`: Lists files in a Google Drive folder (includes shortcut details)
- `listSharedFolders()`: Lists folders shared with the user
- `resolveShortcut(shortcutID:)`: Resolves a Google Drive shortcut to its target file/folder
- `searchFiles(query:)`: Searches for files and folders by name
- `downloadFile(fileID:fileName:to:)`: Downloads a single file
- `downloadBookByM4BFile(m4bFileID:folderID:to:)`: Downloads M4B file and related files

**Authentication Flow**:
1. App launches → `checkAuthenticationStatus()` called
2. If not authenticated → User signs in via `signIn()`
3. Token stored in keychain automatically by Google Sign-In SDK
4. On subsequent launches, authentication is restored

#### `BookFileManager` (FileManager.swift)
- **Location**: `AudioBookPlayer/Managers/FileManager.swift`
- **Type**: Singleton
- **Purpose**: Manages book file operations
- **Key Methods**:
  - `importBook(from url: URL)`: Imports M4B file from local storage
  - `importBookFromGoogleDriveM4B(m4bFileID:folderID:)`: Imports book from Google Drive
  - `queueFirstChapterTranscription(for:)`: Queues first chapter transcription after import (iOS 26+)
    - Parses chapters using ChapterParser
    - Checks if first chapter already transcribed
    - Queues with `.low` priority (doesn't block user actions)
    - Runs in background, silent failures
    - Copies file to app's Documents/Books directory
    - Extracts duration from audio file
    - Automatically searches and downloads cover image if not present
    - Creates `Book` object
  - `importBookFromGoogleDriveM4B(m4bFileID:folderID:)`: Imports from Google Drive
    - Downloads M4B and related files
    - Creates book directory structure
    - Automatically searches and downloads cover image if not present
    - Returns `Book` object
  - `getBooksDirectory()`: Returns path to Books directory

#### `ChapterParser` (ChapterParser.swift)
- **Location**: `AudioBookPlayer/Managers/ChapterParser.swift`
- **Type**: Singleton
- **Purpose**: Shared utility for parsing chapters from audiobook files
- **Chapter Source Priority (CRITICAL):**
  1. **M4B embedded metadata** (highest priority - when implemented)
  2. **CUE file chapters** (when implemented)
  3. **Multiple MP3 files** (when implemented - each file = one chapter)
  4. **Simulated chapters** (LAST RESORT - only if no other source available)
- **Risk Mitigation:**
  - **NEVER** merge multiple chapter sources (e.g., CUE + simulated)
  - If CUE file exists, use ONLY CUE file chapters
  - If M4B metadata exists, use ONLY M4B chapters
  - Simulated chapters are ONLY used when NO other chapter source is available
  - This ensures chapter indices remain stable across app sessions
  - Mixing sources would cause chapter index mismatches and transcription data loss
- **Key Methods**:
  - `parseChapters(from:duration:bookID:)` - Parses chapters from AVAsset and duration
    - Attempts to parse from M4B metadata (when implemented)
    - Falls back to CUE file parsing (when implemented)
    - Falls back to multiple file detection (when implemented)
    - LAST RESORT: Generates simulated chapters if enabled and no other source available
    - Returns array of Chapter objects, sorted by startTime
- **Used By**:
  - `AudioManager` - For parsing chapters during book load
  - `BookFileManager` - For parsing chapters after import to queue first chapter transcription

#### `CoverImageManager`
- **Location**: `AudioBookPlayer/Managers/CoverImageManager.swift`
- **Type**: Singleton (`ObservableObject`)
- **Purpose**: Manages automatic cover image search and download from Google Books API
- **Key Properties**:
  - `@Published var isSearching: Bool` - Whether a cover search is in progress
  - `@Published var searchingBookID: UUID?` - ID of book currently being searched
  - `coversDirectory: URL` - Path to `Documents/Covers/` directory

**Key Methods**:
- `searchAndDownloadCover(for book: Book) async -> URL?`: Searches Google Books API and downloads cover
  - Cleans book title (removes brackets, ASINs, etc.)
  - Searches using title and author
  - Converts HTTP image URLs to HTTPS for App Transport Security
  - Downloads and saves image as JPEG
  - Returns local file URL or nil if not found
- `retryFailedDownloads(for books: [Book]) async -> [UUID: URL]`: Retries cover downloads on app launch
  - Filters books without covers
  - Downloads with rate limiting (0.5s delay between requests)
  - Returns dictionary mapping book IDs to cover URLs

**State Management**:
- Uses synchronous state resets to prevent race conditions
- Resets `isSearching` and `searchingBookID` before function returns
- Checks `searchingBookID == book.id` before resetting to prevent cross-book interference

#### `PersistenceManager`
- **Location**: `AudioBookPlayer/Managers/PersistenceManager.swift`
- **Type**: Singleton
- **Purpose**: Handles data persistence using UserDefaults
- **Key Methods**:
  - `saveBooks(_ books: [Book])`: Saves books array
  - `loadBooks() -> [Book]`: Loads books array
  - `saveSettings(_ settings: PlaybackSettings)`: Saves settings
  - `loadSettings() -> PlaybackSettings`: Loads settings (with backward compatibility)
  - `saveCurrentBookID(_ bookID: UUID?)`: Saves current book ID
  - `loadCurrentBookID() -> UUID?`: Loads current book ID
  - `savePosition(for bookID: UUID, position: TimeInterval)`: Saves playback position
  - `loadPosition(for bookID: UUID) -> TimeInterval`: Loads playback position

#### `TranscriptionDatabase`
- **Location**: `AudioBookPlayer/Managers/TranscriptionDatabase.swift`
- **Type**: Singleton
- **Purpose**: Manages SQLite database for persistent transcription storage
- **Technology**: GRDB.swift wrapper for SQLite
- **Key Properties**:
  - `static let shared = TranscriptionDatabase()`: Singleton instance
  - `private let dbQueue: DatabaseQueue`: Thread-safe database queue

**Key Methods**:
- `init()`: Initializes database, creates tables and indexes if needed
- `loadSentences(bookID:startTime:endTime:) async -> [TranscribedSentence]`: Loads sentences in time range (windowed loading)
- `findSentence(bookID:atTime:) async -> TranscribedSentence?`: Finds sentence at specific playback time
- `insertChunk(_ chunk: TranscriptionChunk) async throws`: Inserts transcription chunk with all sentences (batch insert)
- `getTranscriptionProgress(bookID:) async -> TimeInterval`: Gets latest transcribed time for a book
- `getNextTranscriptionStartTime(bookID:) async -> TimeInterval`: Gets next chunk start time for incremental transcription
- `getChunkCount(bookID:) async -> Int`: Gets number of transcribed chunks for a book
- `clearTranscription(bookID:) async throws`: Deletes all transcription data for a book

**Database Schema**:
- `sentences` table: Individual transcribed sentences with absolute timestamps
- `chunks` table: Metadata for transcription chunks (2-minute segments)
- Indexes on `(book_id, start_time)` for efficient time-range queries

**Thread Safety**: Uses GRDB's `DatabaseQueue` for thread-safe concurrent reads and serialized writes

#### `TranscriptionManager`
- **Location**: `AudioBookPlayer/Managers/TranscriptionManager.swift`
- **Type**: Singleton (`ObservableObject`)
- **Purpose**: Orchestrates transcription workflow using iOS 26 Speech Framework
- **Key Properties**:
  - `@Published var isTranscribing: Bool`: Whether transcription is in progress
  - `@Published var progress: Double`: Transcription progress (0.0 to 1.0)
  - `@Published var transcribedSentences: [TranscribedSentence]`: Currently loaded sentences for display
  - `@Published var errorMessage: String?`: Error message if transcription fails
  - `@Published var currentStatus: String`: Current transcription status message

**Key Methods**:
- `transcribeChunk(book:startTime:) async`: Transcribes a 2-minute chunk starting at specified time
  - Extracts audio segment from book
  - Creates `SpeechTranscriber` with English locale
  - Processes audio through `SpeechAnalyzer`
  - Extracts sentences with timestamps
  - Applies timestamp offset and rounds to 0.1s precision
  - Batch inserts into database
- `loadSentencesForDisplay(bookID:startTime:endTime:) async`: Loads sentences in time range for display (windowed loading)
- `isTranscriptionAvailable() async -> Bool`: Checks iOS version, Speech Framework availability, and English locale support
- `checkIfTranscriptionNeededAtSeekPosition(bookID:seekTime:chunkSize:) async -> TimeInterval?`: Determines if transcription is needed at seek position

**Transcription Process**:
1. Extract 2-minute audio segment using `AVAssetExportSession`
2. Create `SpeechTranscriber` with `.general` preset for automatic punctuation
3. Create `SpeechAnalyzer` with transcriber module
4. Process audio and extract sentences from `AttributedString.runs` with `audioTimeRange` attribute
5. Apply timestamp offset (chunk start time)
6. Round timestamps to 0.1s precision
7. Batch insert into SQLite database

#### `TranscriptionQueue`
- **Location**: `AudioBookPlayer/Managers/TranscriptionQueue.swift`
- **Type**: Singleton (`actor`)
- **Purpose**: Manages background transcription task queue with priority system
- **Key Properties**:
  - `static let shared = TranscriptionQueue()`: Singleton instance
  - `private var queuedTasks: [TranscriptionTask]`: Priority queue of pending tasks
  - `private var runningTasks: [UUID: TranscriptionTask]`: Currently executing tasks
  - `private let maxConcurrentTasks = 5`: Maximum concurrent transcription tasks
  - `private var processingTask: Task<Void, Never>?`: Background processing task

**Task Priority System**:
- `.high`: Current book's transcription needs
- `.medium`: Books in progress with gaps
- `.low`: Books not yet started

**Key Methods**:
- `enqueue(_ task: TranscriptionTask)`: Adds task to queue with duplicate prevention
- `detectTranscriptionGaps(books:currentBookID:) async`: Detects missing transcription chunks for all books
  - Checks each book for gaps
  - Queues initial chunk for books without transcription
  - Queues chunks for books with gaps ahead of playback position
  - Uses power-aware processing (checks battery level)
- `shouldProcess() async -> Bool`: Checks if transcription should proceed based on power state
  - Returns `true` if device is charging or battery > 50%
  - Uses `MainActor.run` to access `UIDevice` (MainActor-isolated)

**Concurrency Model**:
- Actor ensures thread-safe task management
- Maximum 5 concurrent tasks
- Oldest task cancelled if limit exceeded
- Tasks not cancelled on seek (allowed to complete)

**Integration Points**:
- Called from `AudioBookPlayerApp.loadInitialData()` for gap detection on app launch
- Called from `LibraryView` import hooks for auto-transcription on import
- Called from `AIMagicControlsView` for buffer monitoring and seek detection


### 4. Views

#### `ContentView`
- **Location**: `AudioBookPlayer/ContentView.swift`
- **Purpose**: Main tab view container
- **Structure**: TabView with three tabs:
  1. LibraryView
  2. PlayerView
  3. SettingsView
- **Responsibilities**:
  - Observes `AppState` changes
  - Auto-switches to Player tab when book is selected (using DispatchQueue.main.async for reliable switching)
  - Saves books and settings when they change
  - Updates book position in both `currentBook` and `books` array from `AudioManager` for real-time library updates
  - Displays interruption toast notifications
  - Manages full-screen sleep timer overlay

#### `LibraryView`
- **Location**: `AudioBookPlayer/Views/LibraryView.swift`
- **Purpose**: Displays list of books with progress tracking
- **Features**:
  - Empty state when no books
  - Book list with cover art, title, author, and progress indicators
  - Real-time progress updates as books are played
  - Swipe-to-delete with confirmation
  - Import button (+)
  - Auto-plays and switches to Player tab when book is selected
- **Subviews**:
  - `BookRow`: Individual book row component with status badges and chapter progress
  - `ImportView`: Import interface

**Key Methods**:
- `selectBook(_ book: Book)`: Selects a book, loads position, starts playback, and switches to Player tab
- `deleteBook(_ book: Book)`: Deletes book and all associated files
- `performBookDeletion(_ book: Book)`: Actually deletes files from disk

#### `PlayerView`
- **Location**: `AudioBookPlayer/Views/PlayerView.swift`
- **Purpose**: Audio player interface
- **Features**:
  - Playback controls (play, pause, skip)
  - Progress slider
  - Time display
  - Playback speed button with quick selection (0.5x - 2.0x)
  - Sleep timer button with duration selection (15, 30, 45, 60 minutes)
  - Chapter navigation (next/previous)
  - Chapter list with current chapter indicator
  - Cover art display with "Searching for cover..." indicator
  - Error display
- **Observations**:
  - Observes `AudioManager` for playback state, chapters, speed, and sleep timer
  - Observes `AppState` for current book
  - Observes `CoverImageManager` for cover search progress

#### `AIMagicControlsView`
- **Location**: `AudioBookPlayer/Views/AIMagicControlsView.swift`
- **Purpose**: Dedicated view for displaying transcription and AI Magic controls
- **Availability**: iOS 26.0+ only
- **Layout**: 80/20 split (transcription content / action button)
- **Key Features**:
  - Windowed sentence loading (30s before, 75s after current playback position)
  - Real-time sentence highlighting synchronized with playback
  - Auto-scroll to current sentence
  - Dynamic window updates when playback position changes significantly (>10s)
  - Status display in navigation bar (emoji + short text when transcribing)
  - "What did I miss?" button (placeholder for future feature)

**Key Properties**:
- `@State private var highlightedSentenceID: UUID?`: Currently highlighted sentence
- `@State private var isLoading: Bool`: Loading state for sentence fetching
- `@State private var lastPlaybackTime: TimeInterval`: Tracks playback position for seek detection
- `@State private var seekDebounceTask: Task<Void, Never>?`: Debounce task for seek detection
- `@State private var bufferCheckTask: Task<Void, Never>?`: Background task for buffer monitoring

**Key Methods**:
- `loadInitialSentences() async`: Loads windowed sentences on view appear
- `handleBookChange(newID:) async`: Reloads sentences when book changes
- `updateHighlight(for:)`: Updates highlighted sentence based on playback time
- `handleSeek(to:) async`: Detects seek events and triggers transcription if needed
- `checkBufferAndTranscribeIfNeeded() async`: Monitors buffer and transcribes when low
- `startBufferMonitoring()`: Starts background task for buffer monitoring

**Transcription Status Display**:
- Navigation bar shows emoji + short status when `isTranscribing` is true:
  - ⚙️ Preparing...
  - 📚 Checking model...
  - ✂️ Extracting...
  - 🎤 Transcribing...
  - 💾 Saving...
  - ✅ Complete

**Integration Points**:
- Observes `transcriptionManager.transcribedSentences` for display
- Observes `audioManager.currentTime` for highlighting and seek detection
- Observes `audioManager.isPlaying` for highlighting control
- Calls `TranscriptionQueue` for buffer monitoring and seek-triggered transcription

#### `TranscriptionDebugDashboardView`
- **Location**: `AudioBookPlayer/Views/TranscriptionDebugDashboardView.swift`
- **Purpose**: Debug dashboard for monitoring transcription instances and queue status
- **Availability**: iOS 26.0+ only
- **Access**: Available via gear icon button in `PlayerView` (top right)

**Key Features**:
- Real-time metrics display (total instances, running, completed, failed, average duration, battery impact)
- Queue status monitoring (queued tasks, running tasks, max concurrent)
- Running instances list with detailed information
- All instances history (reversed chronological order)
- Auto-refresh every 1 second

**Instance Information Display**:
- Book title (bold, subheadline)
- Chapter title and time range (caption, secondary color)
- Status indicator (color-coded circle: orange=running, green=completed, red=failed, gray=cancelled)
- Start/end timestamps
- Duration (for completed instances)
- Sentence count
- Error messages (for failed instances)

**Key Properties**:
- `@ObservedObject private var tracker = TranscriptionInstanceTracker.shared`: Instance tracker
- `@State private var queuedTasks: [TranscriptionQueue.TranscriptionTask]`: Current queue state
- `@State private var runningTasks: [TranscriptionQueue.TranscriptionTask]`: Currently running tasks
- `@State private var queueStatus: (queued: Int, running: Int, maxConcurrent: Int)`: Queue metrics
- `@State private var refreshTimer: Timer?`: Auto-refresh timer

**Integration Points**:
- Accessed from `PlayerView` via debug button (gearshape icon)
- Displays data from `TranscriptionInstanceTracker` and `TranscriptionQueue`

#### `TranscriptionInstanceTracker`
- **Location**: `AudioBookPlayer/Managers/TranscriptionInstanceTracker.swift`
- **Type**: Singleton (`ObservableObject`)
- **Purpose**: Tracks lifecycle of all transcription instances for debugging and monitoring
- **Availability**: iOS 26.0+ only

**Key Properties**:
- `@Published private(set) var instances: [TranscriptionInstance]`: All tracked instances
- `@Published private(set) var updateTrigger: Int`: Force UI updates counter

**TranscriptionInstance Structure**:
- `id: UUID`: Unique instance identifier
- `bookTitle: String`: Book title
- `chapterTitle: String`: Chapter title (e.g., "Chapter 1", "Chapter 14")
- `startTime: TimeInterval`: Audio time range start
- `endTime: TimeInterval`: Audio time range end
- `startedAt: Date`: When transcription started
- `endedAt: Date?`: When transcription ended (nil if still running)
- `status: InstanceStatus`: Current status (running, completed, failed, cancelled)
- `sentenceCount: Int`: Number of sentences transcribed
- `errorMessage: String?`: Error message if failed

**Key Methods**:
- `startInstance(bookTitle:chapterTitle:startTime:endTime:) -> UUID`: Creates and tracks new instance
- `completeInstance(id:sentenceCount:)`: Marks instance as completed with sentence count
- `failInstance(id:error:)`: Marks instance as failed with error message
- `cancelInstance(id:)`: Marks instance as cancelled

**Computed Properties**:
- `runningInstances: [TranscriptionInstance]`: Currently running instances
- `completedInstances: [TranscriptionInstance]`: Successfully completed instances
- `failedInstances: [TranscriptionInstance]`: Failed instances
- `totalRunningCount: Int`: Count of running instances
- `averageDuration: TimeInterval`: Average duration of completed instances
- `estimatedBatteryImpact: String`: Human-readable battery impact estimate

**Integration Points**:
- Called from `TranscriptionManager.transcribeChapter()` to track instance lifecycle
- Observed by `TranscriptionDebugDashboardView` for display


#### `SleepTimerFullScreenView`
- **Location**: `AudioBookPlayer/Views/SleepTimerFullScreenView.swift`
- **Purpose**: Full-screen sleep timer interface
- **Features**:
  - Black background covering entire screen (including tab bar)
  - Three-section layout (left: stop, center: timer, right: extend)
  - Large red countdown clock (monospaced, bold, rounded design)
  - Circular tick indicator with 60 ticks showing progress
  - Ticks turn from red to gray clockwise from top as time elapses
  - Stop button (left) - cancels timer and returns to player
  - Extend button (right) - adds 10 minutes to timer
  - Works in both portrait and landscape orientations
- **Components**:
  - `CircularTickIndicator`: Renders 60 ticks in a circle around the clock
  - `TickView`: Individual tick with radial orientation
- **Observations**:
  - Observes `AudioManager` for timer state and remaining time

#### `SettingsView`
- **Location**: `AudioBookPlayer/Views/SettingsView.swift`
- **Purpose**: App settings interface
- **Features**:
  - Skip interval configuration
  - Chapter simulation toggle and chapter length picker
  - Storage information (total books, downloaded books)
- **Note**: Playback speed and sleep timer controls have been moved to the player view for quick access

#### `GoogleDrivePickerView`
- **Location**: `AudioBookPlayer/Views/GoogleDrivePickerView.swift`
- **Purpose**: Google Drive file browser with search and shortcut support
- **Features**:
  - Authentication interface
  - Hierarchical folder navigation with navigation stack
  - Shortcut resolution (follows shortcuts to target folders)
  - Search functionality to find files and folders by name
  - File listing (folders, files, and shortcuts)
  - M4B file selection
  - Automatic related file discovery
  - **Smart folder detection**: When selecting files from search results, automatically fetches the file's actual parent folder ID to ensure correct import location
- **Navigation**: Uses navigation stack to browse folders, supports shortcuts and search results

#### `DocumentPicker`
- **Location**: `AudioBookPlayer/Views/DocumentPicker.swift`
- **Purpose**: Local file picker wrapper
- **Features**: Presents iOS document picker for M4B files

## Data Flow

### Book Import Flow

```
User Action (Import from Files)
    │
    ▼
DocumentPicker → User selects file
    │
    ▼
ImportView.importBook(from: URL)
    │
    ▼
BookFileManager.importBook(from: URL)
    │
    ├─→ Copies file to Documents/Books/
    ├─→ Extracts duration from AVAsset
    ├─→ CoverImageManager.searchAndDownloadCover() (if no cover)
    │   ├─→ Searches Google Books API
    │   ├─→ Downloads cover image
    │   └─→ Saves to Documents/Covers/{bookID}.jpg
    └─→ Creates Book object (with coverImageURL if found)
    │
    ▼
AppState.books.append(book)
    │
    ▼
PersistenceManager.saveBooks(books)
    │
    ├─→ Saved to UserDefaults
    │
    └─→ Background: BookFileManager.queueFirstChapterTranscription() (iOS 26+)
        ├─→ Parses chapters using ChapterParser
        ├─→ Checks if first chapter already transcribed
        └─→ Queues first chapter transcription with .low priority
            └─→ TranscriptionQueue processes in background
```

### Google Drive Import Flow

```
User Action (Import from Google Drive)
    │
    ▼
GoogleDrivePickerView
    │
    ├─→ GoogleDriveManager.signIn() (if not authenticated)
    ├─→ GoogleDriveManager.listFiles() (browse folders)
    └─→ User selects M4B file
    │
    ├─→ If selected from search results:
    │   └─→ GoogleDriveManager.getFileMetadata() (fetches parent folder ID)
    │       └─→ Uses actual parent folder ID instead of search context
    │
    ▼
ImportView.importBookFromGoogleDriveM4B()
    │
    ▼
BookFileManager.importBookFromGoogleDriveM4B()
    │
    ├─→ GoogleDriveManager.downloadBookByM4BFile()
    │   ├─→ Downloads M4B file
    │   ├─→ Finds related files (CUE, JPG, NFO)
    │   └─→ Downloads all related files
    ├─→ Extracts duration
    ├─→ CoverImageManager.searchAndDownloadCover() (if no cover from Drive)
    │   ├─→ Searches Google Books API
    │   ├─→ Downloads cover image
    │   └─→ Saves to Documents/Covers/{bookID}.jpg
    └─→ Creates Book object (with coverImageURL if found)
    │
    ▼
AppState.books.append(book)
    │
    ▼
PersistenceManager.saveBooks(books)
    │
    └─→ Background: BookFileManager.queueFirstChapterTranscription() (iOS 26+)
        ├─→ Parses chapters using ChapterParser
        ├─→ Checks if first chapter already transcribed
        └─→ Queues first chapter transcription with .low priority
            └─→ TranscriptionQueue processes in background
```

### Playback Flow

```
User taps book in LibraryView
    │
    ▼
LibraryView.selectBook(book)
    │
    ├─→ AppState.currentBook = book
    └─→ ContentView detects change → switches to Player tab
    │
    ▼
PlayerView appears
    │
    ├─→ Observes AppState.currentBook
    └─→ Calls AudioManager.loadBook(book)
    │
    ▼
AudioManager.loadBook(book)
    │
    ├─→ Resolves file path
    ├─→ Creates AVPlayerItem
    ├─→ Creates AVPlayer
    ├─→ Sets up time observer
    ├─→ Loads duration and parses chapters
    │   ├─→ If no chapters found and simulateChapters enabled
    │   └─→ Generates simulated chapters based on duration
    └─→ Updates @Published properties
    │
    ▼
PlayerView updates UI
    │
    ├─→ Shows book info and cover art
    ├─→ Shows playback controls
    ├─→ Displays current time
    └─→ Shows chapter list (real or simulated)
```

### App Launch Flow

```
App Launch (AudioBookPlayerApp)
    │
    ▼
loadInitialData()
    │
    ├─→ PersistenceManager.loadBooks()
    ├─→ PersistenceManager.loadSettings()
    ├─→ PersistenceManager.loadCurrentBookID()
    ├─→ PersistenceManager.loadPosition() (for current book)
    └─→ Task: CoverImageManager.retryFailedDownloads()
        │
        ├─→ Filters books without covers
        ├─→ For each book: searchAndDownloadCover()
        │   ├─→ Searches Google Books API
        │   └─→ Downloads cover if found
        └─→ Updates AppState.books with new covers
            │
            └─→ PersistenceManager.saveBooks()
```

### Position Tracking Flow

```
AudioManager.timeObserver fires
    │
    ▼
AudioManager.currentTime updated
    │
    ▼
ContentView.onReceive(AudioManager.$currentTime)
    │
    ├─→ Updates AppState.currentBook.currentPosition
    ├─→ Updates AppState.books[index].currentPosition (for library view)
    └─→ PersistenceManager.savePosition()
    │
    └─→ Saved to UserDefaults
```

### Book Selection Flow

```
User taps book in LibraryView
    │
    ▼
LibraryView.selectBook(book)
    │
    ├─→ Loads position from PersistenceManager
    ├─→ Updates AppState.currentBook
    ├─→ ContentView detects change → switches to Player tab (via DispatchQueue.main.async)
    ├─→ AudioManager.loadBook(book)
    └─→ AudioManager.play()
    │
    ▼
Playback starts from saved position
```

## Interaction Diagrams

### Manager Dependencies

```
AppState
  │
  ├─→ Uses PersistenceManager (loads/saves data)
  └─→ Observed by all Views

AudioManager
  │
  ├─→ Uses AVFoundation (AVPlayer, AVPlayerItem)
  ├─→ Uses PersistenceManager (loads/saves settings for speed and chapter simulation)
  ├─→ Manages sleep timer countdown with async Task
  └─→ Observed by PlayerView, SleepTimerFullScreenView, ContentView

GoogleDriveManager
  │
  ├─→ Uses GoogleSignIn SDK
  ├─→ Uses URLSession (for API calls)
  └─→ Observed by GoogleDrivePickerView

BookFileManager
  │
  ├─→ Uses FileManager (file operations)
  ├─→ Uses AVFoundation (duration extraction)
  ├─→ Uses GoogleDriveManager (for Drive imports)
  ├─→ Uses CoverImageManager (for automatic cover download)
  └─→ Uses ChapterParser (for chapter parsing after import)
  └─→ Uses TranscriptionQueue (for auto-transcription on import, iOS 26+)

CoverImageManager
  │
  ├─→ Uses URLSession (for Google Books API and image downloads)
  ├─→ Uses UIKit (UIImage for image processing)
  └─→ Observed by PlayerView (for search progress)

PersistenceManager
  │
  └─→ Uses UserDefaults (storage)
```

### View Hierarchy

```
AudioBookPlayerApp
  └─→ ContentView
       ├─→ LibraryView
       │    ├─→ BookRow
       │    └─→ ImportView
       │         ├─→ DocumentPicker
       │         └─→ GoogleDrivePickerView
       ├─→ PlayerView
       └─→ SettingsView
       
       // Full-screen overlays (when active)
       └─→ SleepTimerFullScreenView (overlays entire screen when timer active)
            ├─→ CircularTickIndicator
            │    └─→ TickView (60 instances)
            ├─→ Stop Button (left section)
            ├─→ Timer Display (center section)
            └─→ Extend Button (right section)
```

## Key Design Patterns

### 1. Singleton Pattern
- All managers are singletons (`static let shared`)
- Ensures single instance across the app
- Easy access from anywhere: `AudioManager.shared`

### 2. ObservableObject Pattern
- Managers that need to update UI are `ObservableObject`
- Views observe them using `@ObservedObject` or `@StateObject`
- Changes to `@Published` properties trigger UI updates
- Examples: `AudioManager`, `GoogleDriveManager`, `CoverImageManager`, `AppState`

### 3. MVVM Pattern
- **Models**: Data structures (Book, Chapter, etc.)
- **Views**: SwiftUI views (LibraryView, PlayerView, etc.)
- **ViewModels**: Managers act as ViewModels (AudioManager, etc.)

### 4. Dependency Injection
- `AppState` injected via `@EnvironmentObject`
- Managers accessed via singleton pattern
- Makes testing easier (can mock managers)

### 5. Async/Await Pattern
- Modern Swift concurrency for network operations
- `async/await` used throughout for file downloads, API calls
- `@MainActor` ensures UI updates happen on main thread
- Synchronous state resets prevent race conditions

## Threading Model

- **Main Thread**: All UI updates and SwiftUI operations
- **Background Threads**: 
  - File downloads (GoogleDriveManager)
  - Duration extraction (BookFileManager)
  - File operations
- **MainActor**: Used for UI-related async operations
  - `AudioManager` updates use `@MainActor` or `MainActor.run`
  - `GoogleDriveManager` progress updates use `MainActor.run`
  - `TranscriptionManager` UI state updates use `MainActor.run`
  - `TranscriptionQueue.shouldProcess()` uses `MainActor.run` for UIDevice access
- **Actors**: 
  - `TranscriptionQueue`: Actor for thread-safe concurrent task management
  - Uses `Task.detached` for background processing
  - Ensures thread-safe access to task queue and running tasks
- **Database Threading**:
  - `TranscriptionDatabase`: Uses GRDB's `DatabaseQueue` for thread-safe operations
  - Read operations: Concurrent reads allowed via `dbQueue.read`
  - Write operations: Serialized writes via `dbQueue.write`

## Error Handling

- **AudioManager**: Sets `playbackError` property, displayed in UI
- **GoogleDriveManager**: Throws errors, caught by views and displayed
- **File Operations**: Try-catch blocks, errors logged and handled gracefully
- **Network Operations**: HTTP status code checking, error messages displayed to user

## Persistence Strategy

- **UserDefaults**: Used for app configuration data
  - Books array (JSON encoded)
  - Settings (JSON encoded with backward compatibility)
  - Current book ID
  - Playback positions (per book)
  - Books array (JSON encoded)
  - Settings (JSON encoded with backward compatibility)
  - Current book ID
  - Playback positions (per book)
- **SQLite Database**: Used for transcription data
  - Database file: `Documents/transcription.db`
  - Managed by GRDB.swift wrapper
  - Tables: `sentences`, `chunks`
  - Thread-safe via `DatabaseQueue`
  - Indexes optimized for time-range queries
  - See `TRANSCRIPTION_DATABASE.md` for detailed schema
- **File System**: 
  - Books stored in `Documents/Books/`
  - Google Drive books in subdirectories: `Documents/Books/{folderID}/`
  - Cover images stored in `Documents/Covers/{bookID}.jpg`
  - Transcription temporary files: System temp directory (cleaned up after use)
  - Files organized by import source
  - Books stored in `Documents/Books/`
  - Google Drive books in subdirectories: `Documents/Books/{folderID}/`
  - Cover images stored in `Documents/Covers/{bookID}.jpg`
  - Files organized by import source

## Security Considerations

- **Security-Scoped Resources**: Used for files outside app sandbox
- **Google OAuth**: Tokens stored securely in keychain by Google Sign-In SDK
- **File Access**: Proper cleanup of security-scoped access
- **Sensitive Data**: OAuth Client ID should not be committed (in .gitignore)

---

This architecture provides a clean separation of concerns, making the codebase maintainable and testable. Each component has a clear responsibility, and the flow of data is well-defined.


