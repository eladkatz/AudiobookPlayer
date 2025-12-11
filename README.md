# AudioBook Player

A modern iOS audiobook player app built with SwiftUI, featuring local file import and Google Drive integration.

## Features

- 📚 **Library Management**: Organize and manage your audiobook collection
- 🎵 **Audio Playback**: Full-featured audio player with playback controls
- ⏯️ **Playback Controls**: Play, pause, skip forward/backward, speed control
- 📍 **Position Tracking**: Automatically saves and restores playback position
- ☁️ **Google Drive Integration**: Import audiobooks directly from Google Drive
- 📁 **Local File Import**: Import M4B files from your device
- 🖼️ **Cover Art Support**: Display book cover images
- ⚙️ **Customizable Settings**: Adjust playback speed, skip intervals, and more
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
│   │   └── PersistenceManager.swift # Data persistence
│   ├── Views/
│   │   ├── LibraryView.swift       # Book library
│   │   ├── PlayerView.swift        # Audio player interface
│   │   ├── SettingsView.swift      # App settings
│   │   ├── DocumentPicker.swift    # Local file picker
│   │   └── GoogleDrivePickerView.swift # Google Drive file browser
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
- Playback speed adjustment
- Error handling

### GoogleDriveManager
Handles Google Drive integration:
- OAuth authentication
- File browsing and navigation
- File downloading with progress tracking
- Automatic discovery of related files (CUE, images, NFO)

### BookFileManager
Manages book files:
- Importing M4B files from local storage
- Importing from Google Drive
- File organization in app's Documents directory
- Duration extraction from audio files

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

1. Tap a book in the Library to open it
2. Use the player controls:
   - Play/Pause
   - Skip forward/backward (configurable intervals)
   - Adjust playback speed
   - Seek using the progress slider

### Managing Books

- **Delete**: Swipe left on a book and tap "Delete", or use the standard swipe-to-delete gesture
- **Position**: Playback position is automatically saved and restored

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

- [ ] CUE file parsing for chapter navigation
- [ ] Sleep timer functionality
- [ ] Playlist support
- [ ] Cloud sync across devices
- [ ] Widget support
- [ ] CarPlay integration
- [ ] Background audio controls

## Support

For issues, questions, or contributions, please open an issue on GitHub.

---

**Built with ❤️ using SwiftUI and AVFoundation**

