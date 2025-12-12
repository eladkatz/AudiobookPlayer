# AudioBook Player

A modern iOS audiobook player app built with SwiftUI, featuring local file import and Google Drive integration.

## Features

- 📚 **Library Management**: Organize and manage your audiobook collection with visual progress tracking
- 🎵 **Audio Playback**: Full-featured audio player with playback controls
- ⏯️ **Playback Controls**: Play, pause, skip forward/backward, speed control
- 📍 **Position Tracking**: Automatically saves and restores playback position for each book
- 📊 **Progress Display**: Chapter-based progress bars and status indicators (Started, In-Progress, Done) in library view
- 📖 **Chapter Navigation**: Navigate by chapters with next/previous controls
- 🔄 **Simulated Chapters**: Automatically generate chapters for books without CUE files (configurable length)
- ⏱️ **Sleep Timer**: Full-screen sleep timer with visual countdown and progress indicator
- ⚡ **Playback Speed Control**: Quick access speed selector (0.5x - 2.0x) directly from player
- ☁️ **Google Drive Integration**: Import audiobooks directly from Google Drive with folder navigation and search
- 🔗 **Google Drive Shortcuts**: Navigate through Google Drive shortcuts as if they were folders
- 🔍 **Google Drive Search**: Search for files and folders by name in Google Drive
- 📁 **Local File Import**: Import M4B files from your device
- 🖼️ **Automatic Cover Art**: Automatically searches and downloads book covers from Google Books API
- 🔔 **Audio Interruption Handling**: Automatically pauses and resumes playback with configurable rewind on interruptions
- 📱 **Now Playing Integration**: Lock screen and Control Center controls with chapter navigation and speed control
- ⚙️ **Customizable Settings**: Adjust skip intervals, chapter simulation, interruption handling, and more
- 💾 **Persistent Storage**: All data is saved locally and persists between app launches

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Apple Developer Account (for device deployment)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/eladkatz/AudiobookPlayer.git
cd AudiobookPlayer
```

### 2. Open in Xcode

```bash
open AudioBookPlayer.xcodeproj
```

### 3. Configure Signing

1. Select the **AudioBookPlayer** project in Xcode
2. Go to **Signing & Capabilities**
3. Check **"Automatically manage signing"**
4. Select your **Team** from the dropdown

### 4. Run the App

- Press **⌘ + R** or click the **Play** button
- Select an iOS Simulator or connected device
- The app will build and launch

For detailed setup instructions, see [QUICK_START.md](QUICK_START.md).

## Project Structure

```
AudioBookPlayer/
├── AudioBookPlayer/
│   ├── AudioBookPlayerApp.swift    # App entry point
│   ├── ContentView.swift            # Main tab view
│   ├── Models/
│   │   └── Models.swift            # Data models (Book, Chapter, etc.)
│   ├── Managers/
│   │   ├── AudioManager.swift      # Audio playback management
│   │   ├── FileManager.swift       # File import and management
│   │   ├── GoogleDriveManager.swift # Google Drive integration
│   │   ├── CoverImageManager.swift  # Automatic cover image search and download
│   │   └── PersistenceManager.swift # Data persistence
│   ├── Views/
│   │   ├── LibraryView.swift       # Book library
│   │   ├── PlayerView.swift        # Audio player interface
│   │   ├── SettingsView.swift      # App settings
│   │   ├── DocumentPicker.swift    # Local file picker
│   │   ├── GoogleDrivePickerView.swift # Google Drive file browser
│   │   └── SleepTimerFullScreenView.swift # Full-screen sleep timer
│   └── Assets.xcassets/            # App icons and images
└── Documentation/
    ├── README.md                   # This file
    ├── ARCHITECTURE.md             # Architecture documentation
    ├── CONTRIBUTING.md             # Contribution guidelines
    ├── QUICK_START.md              # Quick start guide
    └── GOOGLE_DRIVE_SETUP.md      # Google Drive setup instructions
```

## Architecture

The app follows a **Model-View-ViewModel (MVVM)** architecture pattern with managers for business logic:

- **Models**: Data structures (`Book`, `Chapter`, `PlaybackSettings`, `AppState`)
- **Views**: SwiftUI views that display the UI
- **Managers**: Business logic and state management (singletons)
- **Persistence**: UserDefaults for data storage

For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Key Components

### AudioManager
Manages audio playback using AVFoundation. Handles:
- Loading and playing M4B files
- Playback controls (play, pause, seek)
- Time tracking and position updates
- Playback speed adjustment (0.5x - 2.0x, persisted to settings)
- Chapter navigation (next/previous)
- Simulated chapter generation for books without CUE files
- Sleep timer with countdown and automatic playback pause
- Audio interruption handling (pauses on notifications/calls, resumes with configurable rewind)
- Now Playing integration (Lock Screen/Control Center) with chapter navigation and speed control
- Error handling

### GoogleDriveManager
Handles Google Drive integration:
- OAuth authentication with persistent sign-in (keychain-based)
- File browsing and navigation with hierarchical folder support
- Shortcut resolution (follows Google Drive shortcuts to target folders)
- Search functionality to find files and folders by name
- File downloading with progress tracking
- Automatic discovery of related files (CUE, images, NFO)

### BookFileManager
Manages book files:
- Importing M4B files from local storage
- Importing from Google Drive
- File organization in app's Documents directory
- Duration extraction from audio files
- Automatic cover image search during import

### CoverImageManager
Handles automatic cover image discovery:
- Searches Google Books API using book title and author
- Downloads cover images automatically when books are imported
- Converts HTTP to HTTPS for App Transport Security compliance
- Retries failed downloads on app launch
- Caches downloaded covers in `Documents/Covers/` directory

### PersistenceManager
Handles data persistence:
- Saving/loading books
- Playback position tracking
- Settings persistence
- Current book tracking

## Google Drive Integration

The app supports importing audiobooks directly from Google Drive. To set this up:

1. Follow the instructions in [GOOGLE_DRIVE_SETUP.md](GOOGLE_DRIVE_SETUP.md)
2. Create a Google Cloud Project
3. Enable Google Drive API
4. Create OAuth 2.0 credentials
5. Add your Client ID to `GoogleDriveManager.swift`

## Supported File Formats

- **Audio**: M4B (MPEG-4 Audio Book)
- **Metadata**: CUE files (for chapter information)
- **Images**: JPEG/JPG (for cover art)
- **Metadata**: NFO files (for future use)

## Usage

### Importing Books

1. **From Local Files**:
   - Tap the **+** button in the Library
   - Select "Import from Files"
   - Choose an M4B file from your device

2. **From Google Drive**:
   - Tap the **+** button in the Library
   - Select "Import from Google Drive"
   - Sign in with your Google account
   - Navigate to folders and select M4B files
   - Related files (images, CUE) are automatically imported

### Playing Books

1. **Selecting a Book**:
   - Tap any book in the Library to automatically start playback and switch to the "Now Playing" view
   - Playback resumes from your last position automatically
2. **Player Controls**:
   - Play/Pause
   - Skip forward/backward (configurable intervals)
   - Adjust playback speed (tap speed button for quick selection: 0.5x - 2.0x)
   - Seek using the progress slider
   - Navigate chapters using next/previous buttons
   - Sleep timer (tap moon icon to set timer: 15, 30, 45, or 60 minutes)
3. **Chapter Navigation**:
   - Books without CUE files automatically get simulated chapters (default: 15 minutes each)
   - Configure chapter length in Settings → Chapters
   - Toggle chapter simulation on/off in Settings
4. **Sleep Timer**:
   - Tap the moon icon in the player controls to activate
   - Full-screen dark mode with large countdown display
   - Visual progress indicator with 60 ticks showing elapsed/remaining time
   - Cancel or extend timer (+10 minutes) directly from full-screen view
   - Automatically pauses playback when timer expires
5. **Library Progress Tracking**:
   - Each book shows its progress status: "Started", "In-Progress", or "Done"
   - Chapter-based progress bar shows how many chapters you've completed
   - "Chapter x/y" display shows current chapter out of total chapters
   - Progress updates in real-time as you listen

### Managing Books

- **Delete**: Swipe left on a book and tap "Delete", or use the standard swipe-to-delete gesture
- **Position**: Playback position is automatically saved and restored for each book independently
- **Progress**: View your reading progress at a glance with status badges and chapter progress bars

## Development

### Building for Device

1. Connect your iOS device via USB
2. Select your device in Xcode's device selector
3. Trust the developer certificate on your device:
   - Settings → General → VPN & Device Management
   - Tap your developer certificate
   - Tap "Trust"
4. Build and run (⌘ + R)

### Code Style

- Follow Swift naming conventions
- Use `MARK:` comments to organize code sections
- Keep functions focused and single-purpose
- Add comments for complex logic

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is open source. See LICENSE file for details.

## Troubleshooting

### Build Errors

- **Signing Issues**: Make sure you're signed into Xcode with your Apple ID
- **Missing Dependencies**: Run `File → Packages → Reset Package Caches`
- **Clean Build**: Product → Clean Build Folder (⇧⌘K)

### Runtime Issues

- **File Not Found**: Make sure files are in the app's Documents directory
- **Google Drive Sign-In Fails**: Check that your email is added as a test user in Google Cloud Console
- **Playback Errors**: Ensure M4B files are valid and not corrupted

## Future Enhancements

- [ ] CUE file parsing for chapter navigation (currently uses simulated chapters)
- [ ] Playlist support
- [ ] Cloud sync across devices
- [ ] Widget support
- [ ] CarPlay integration
- [ ] Background audio controls

## Support

For issues, questions, or contributions, please open an issue on GitHub.

---

**Built with ❤️ using SwiftUI and AVFoundation**


