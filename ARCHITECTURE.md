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
  - `playbackSpeed: Double`
  - `skipForwardInterval: TimeInterval`
  - `skipBackwardInterval: TimeInterval`
  - `sleepTimerEnabled: Bool`
  - `sleepTimerDuration: TimeInterval`
  - `simulateChapters: Bool` - Whether to generate simulated chapters for books without CUE files
  - `simulatedChapterLength: TimeInterval` - Length of simulated chapters in seconds (default: 900 = 15 minutes)
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

**Key Methods**:
- `loadBook(_ book: Book)`: Loads a book for playback
  - Resolves file paths (handles symlinks, searches subdirectories)
  - Creates `AVPlayerItem` and `AVPlayer`
  - Sets up time observers
  - Handles security-scoped resource access
  - Generates simulated chapters if no CUE file exists and simulation is enabled
- `play()`: Starts playback
- `pause()`: Pauses playback
- `seek(to time: TimeInterval)`: Seeks to specific time
- `setPlaybackSpeed(_ speed: Double)`: Adjusts playback speed
- `skipForward()` / `skipBackward()`: Skips by configured intervals
- `nextChapter()` / `previousChapter()`: Navigate between chapters
- `generateSimulatedChapters(duration:chapterLength:)`: Creates evenly-spaced chapters based on duration

**Internal State**:
- `player: AVPlayer?` - AVFoundation player instance
- `playerItem: AVPlayerItem?` - Current player item
- `timeObserver: Any?` - Time update observer
- `isPlayerReady: Bool` - Whether player is ready to play

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
- `checkAuthenticationStatus()`: Checks if user is already signed in
- `signIn(presentingViewController:)`: Signs in with Google
- `signOut()`: Signs out
- `listFiles(in folderID:)`: Lists files in a Google Drive folder
- `listSharedFolders()`: Lists folders shared with the user
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
  - Auto-switches to Player tab when book is selected
  - Saves books and settings when they change
  - Updates book position from `AudioManager`

#### `LibraryView`
- **Location**: `AudioBookPlayer/Views/LibraryView.swift`
- **Purpose**: Displays list of books
- **Features**:
  - Empty state when no books
  - Book list with cover art, title, author
  - Swipe-to-delete with confirmation
  - Import button (+)
- **Subviews**:
  - `BookRow`: Individual book row component
  - `ImportView`: Import interface

**Key Methods**:
- `selectBook(_ book: Book)`: Selects a book to play
- `deleteBook(_ book: Book)`: Deletes book and all associated files
- `performBookDeletion(_ book: Book)`: Actually deletes files from disk

#### `PlayerView`
- **Location**: `AudioBookPlayer/Views/PlayerView.swift`
- **Purpose**: Audio player interface
- **Features**:
  - Playback controls (play, pause, skip)
  - Progress slider
  - Time display
  - Speed control
  - Chapter navigation (next/previous)
  - Chapter list with current chapter indicator
  - Cover art display with "Searching for cover..." indicator
  - Error display
- **Observations**:
  - Observes `AudioManager` for playback state and chapters
  - Observes `AppState` for current book
  - Observes `CoverImageManager` for cover search progress

#### `SettingsView`
- **Location**: `AudioBookPlayer/Views/SettingsView.swift`
- **Purpose**: App settings interface
- **Features**:
  - Playback speed adjustment
  - Skip interval configuration
  - Chapter simulation toggle and chapter length picker
  - Sleep timer settings (UI ready, functionality pending)
  - Storage information (total books, downloaded books)

#### `GoogleDrivePickerView`
- **Location**: `AudioBookPlayer/Views/GoogleDrivePickerView.swift`
- **Purpose**: Google Drive file browser
- **Features**:
  - Authentication interface
  - Folder navigation
  - File listing (folders and files)
  - M4B file selection
  - Automatic related file discovery
- **Navigation**: Uses navigation stack to browse folders

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
    └─→ PersistenceManager.savePosition()
    │
    └─→ Saved to UserDefaults
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
  ├─→ Uses PersistenceManager (loads settings for chapter simulation)
  └─→ Observed by PlayerView

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


