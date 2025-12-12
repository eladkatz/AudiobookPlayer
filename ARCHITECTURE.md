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
    └─→ Saved to UserDefaults
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
  └─→ Uses CoverImageManager (for automatic cover download)

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

## Error Handling

- **AudioManager**: Sets `playbackError` property, displayed in UI
- **GoogleDriveManager**: Throws errors, caught by views and displayed
- **File Operations**: Try-catch blocks, errors logged and handled gracefully
- **Network Operations**: HTTP status code checking, error messages displayed to user

## Persistence Strategy

- **UserDefaults**: Used for all app data
  - Books array (JSON encoded)
  - Settings (JSON encoded with backward compatibility)
  - Current book ID
  - Playback positions (per book)
- **File System**: 
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


