# Release Notes

## Version: Transcription Feature Release
**Base Commit**: `28503047bbcc5a2d1d22b3f69158d7b75046a601` (Fixed layout issues on now playing screen)  
**Current Commit**: `HEAD`

---

## 🎉 Major Features

### ✨ Automatic Audiobook Transcription with Real-Time Captions

This release introduces a comprehensive automatic transcription system that provides real-time captions synchronized with audiobook playback. The feature uses iOS 26's new Speech Framework (`SpeechAnalyzer` and `SpeechTranscriber`) to transcribe audiobooks automatically in the background.

**Key Highlights:**
- **Zero-wait captioning**: Transcription starts automatically when books are imported
- **Background processing**: Transcriptions happen automatically without user intervention
- **Real-time synchronization**: Captions highlight and scroll automatically as you listen
- **Efficient storage**: SQLite database with optimized queries for fast loading
- **Smart buffering**: Automatically transcribes ahead of playback position
- **Seek support**: Automatically transcribes missing segments when seeking

---

## 🎨 User Experience (UX) Changes

### AI Magic Controls View Redesign

**Before:**
- Header section with "AI Magic Controls" title and book name
- Clear Database button (debug feature)
- Status/progress bar section
- "Transcription Results" headline with sentence count
- Sentence numbers (1, 2, 3...) and timestamps displayed
- Transcription content mixed with metadata

**After:**
- **Clean, focused design**: Top 80% dedicated to transcription text only
- **Minimal UI**: Removed all headers, buttons, and metadata from main view
- **Text-only display**: Shows only sentence text (numbers and timestamps removed from display, but still stored)
- **Bottom action button**: "What did I miss?" button in bottom 20% (placeholder for future feature)
- **Status in navigation bar**: Transcription status shown as emoji + short text in navigation bar when active:
  - ⚙️ Preparing...
  - 📚 Checking model...
  - ✂️ Extracting...
  - 🎤 Transcribing...
  - 💾 Saving...
  - ✅ Complete
- **Simplified navigation**: Removed Cancel button, kept only "Done" button

**User Benefits:**
- Cleaner, distraction-free reading experience
- More screen space for actual transcription content
- Status information available but not intrusive
- Better focus on the transcribed text itself

### Automatic Transcription Workflow

**Phase 1: Auto-Transcribe on Import**
- When a book is imported, the first 2-minute chunk is automatically transcribed in the background
- No manual button needed - transcription starts automatically
- Subtle status indicator in navigation bar shows progress

**Phase 2: Windowed Display**
- Transcription view shows a "window" of text: 30 seconds before and 75 seconds after current playback position
- Current sentence is highlighted with blue background
- Past sentences are lowlighted (gray/secondary color)
- Future sentences are also lowlighted
- Auto-scroll centers the current sentence in view

**Phase 3: Automatic Buffer Monitoring**
- System monitors transcription buffer during playback
- When buffer falls below 1 minute remaining (half of 2-minute chunk), automatically transcribes next chunk
- Prevents gaps in transcription during continuous playback
- Duplicate prevention ensures chunks aren't transcribed twice

**Phase 4: Queue System & Gap Detection**
- Background queue system manages up to 5 concurrent transcription tasks
- On app launch, automatically detects gaps in transcription for all books
- Prioritizes current book's transcription needs
- Power-aware: Only processes when device is charging or battery > 50%

**Phase 5: Seeking Support**
- Detects when user seeks to a new position (>30 second jump)
- Automatically transcribes missing chunks at seek position
- Updates display window immediately on seek
- 1-second debounce prevents excessive transcription when scrubbing

---

## 🏗️ Architecture Changes

### New Components

#### 1. `TranscriptionDatabase` (New Manager)
- **Location**: `AudioBookPlayer/Managers/TranscriptionDatabase.swift`
- **Purpose**: Manages SQLite database for persistent transcription storage
- **Technology**: GRDB.swift wrapper for SQLite
- **Key Features**:
  - Thread-safe database operations via `DatabaseQueue`
  - Efficient batch inserts for transcription chunks
  - Optimized queries with indexes on `(book_id, start_time)`
  - Windowed loading for efficient display (loads only visible sentences)
  - Timestamp rounding to 0.1s precision to handle transcriber variations

**Database Schema:**
- `sentences` table: Individual transcribed sentences with absolute timestamps
- `chunks` table: Metadata for transcription chunks (2-minute segments)
- Indexes optimized for time-range queries

#### 2. `TranscriptionQueue` (New Actor)
- **Location**: `AudioBookPlayer/Managers/TranscriptionQueue.swift`
- **Purpose**: Manages background transcription task queue
- **Architecture**: Swift `actor` for thread-safe concurrent task management
- **Key Features**:
  - Priority-based task queue (low, medium, high)
  - Maximum 5 concurrent transcription tasks
  - Automatic oldest task cancellation when limit exceeded
  - Power-aware processing (checks battery level/charging status)
  - Gap detection on app launch
  - No task cancellation on seek (lets tasks complete)

**Task Priorities:**
- **High**: Current book's transcription needs
- **Medium**: Books in progress with gaps
- **Low**: Books not yet started

#### 3. `TranscriptionManager` (Enhanced)
- **Location**: `AudioBookPlayer/Managers/TranscriptionManager.swift`
- **Purpose**: Orchestrates transcription workflow
- **Key Enhancements**:
  - Refactored `transcribeChunk()` method for reusable chunk transcription
  - iOS 26 Speech Framework integration (`SpeechAnalyzer` + `SpeechTranscriber`)
  - Automatic punctuation via `.general` preset
  - Windowed sentence loading for efficient display
  - Seek position transcription checking
  - Compatibility checking (iOS version, locale support)

**Transcription Process:**
1. Extract 2-minute audio segment from book
2. Create `SpeechTranscriber` with English locale
3. Process audio through `SpeechAnalyzer`
4. Extract sentences with timestamps from `AttributedString.runs`
5. Apply timestamp offset (chunk start time)
6. Round timestamps to 0.1s precision
7. Batch insert into SQLite database

#### 4. `AIMagicControlsView` (New View)
- **Location**: `AudioBookPlayer/Views/AIMagicControlsView.swift`
- **Purpose**: Dedicated view for displaying transcription and AI Magic controls
- **Key Features**:
  - 80/20 split layout (transcription / action button)
  - Real-time sentence highlighting synchronized with playback
  - Auto-scroll to current sentence
  - Windowed loading (30s before, 75s after current position)
  - Dynamic window updates when playback position changes significantly
  - Status display in navigation bar (emoji + text)

### Data Models

#### New Models in `Models.swift`:
- `TranscribedSentence`: Represents a single transcribed sentence
  - `id: UUID`
  - `bookID: UUID`
  - `text: String`
  - `startTime: TimeInterval` (absolute time in book)
  - `endTime: TimeInterval` (absolute time in book)
  - `chunkID: UUID`
  - `createdAt: Date`
  
- `TranscriptionChunk`: Represents a transcription chunk metadata
  - `id: UUID`
  - `bookID: UUID`
  - `startTime: TimeInterval`
  - `endTime: TimeInterval`
  - `createdAt: Date`
  - `isComplete: Bool`

### Integration Points

#### `AudioBookPlayerApp.swift`
- **Change**: Added gap detection on app launch
- **Implementation**: Calls `TranscriptionQueue.shared.detectTranscriptionGaps()` in `loadInitialData()`
- **Purpose**: Ensures all books have initial transcription chunks

#### `LibraryView.swift`
- **Change**: Auto-transcribe on book import
- **Implementation**: After successful import, queues first 2-minute chunk via `TranscriptionQueue`
- **Purpose**: Zero-wait captioning experience

#### `PlayerView.swift`
- **Change**: Added AI Magic button (✨ emoji) to chapter navigation section
- **Implementation**: Opens `AIMagicControlsView` as a sheet
- **Purpose**: Access to transcription view

---

## 🔧 Technical Implementation Details

### Speech Framework Integration

**API Used**: iOS 26 Speech Framework
- `SpeechAnalyzer`: Manages audio analysis pipeline
- `SpeechTranscriber`: Performs speech-to-text transcription
- `SpeechTranscriber.Configuration.Preset.general`: Optimized for continuous speech with automatic punctuation
- `SpeechAnalyzer.Module.audioTimeRange`: Enables timestamp extraction

**Locale Support**: English (en-US) only in this version

**Transcription Options**:
- `transcriptionOptions: []` - Empty (uses default behavior)
- `reportingOptions: [.volatileResults]` - Get incremental results
- `attributeOptions: [.audioTimeRange]` - Enable timestamp extraction

### Database Performance

**Optimizations**:
- Indexes on `(book_id, start_time)` for efficient range queries
- Batch inserts for entire chunks (50-100 sentences at once)
- Windowed loading (only loads visible sentences, not entire book)
- Timestamp rounding reduces duplicate detection issues

**Expected Performance**:
- Batch insert of 50 sentences: <10ms
- Range query for 200 sentences: <5ms
- Window updates: <5ms

### Concurrency Model

**Actors**:
- `TranscriptionQueue`: Actor for thread-safe task management
- Uses `Task.detached` for background processing
- MainActor isolation for UI updates

**Thread Safety**:
- `TranscriptionDatabase`: Thread-safe via GRDB's `DatabaseQueue`
- Read operations: Concurrent reads allowed
- Write operations: Serialized writes

### Error Handling

**Transcription Errors**:
- Locale not installed: Automatically downloads English model
- File access errors: Handles security-scoped URLs
- Transcription failures: Error messages displayed in UI
- Database errors: Automatic recreation on corruption

**Power Management**:
- Checks battery level before processing
- Defers transcription when battery < 50% and not charging
- Processes immediately when plugged in or battery > 50%

---

## 📊 Statistics

**Files Changed**: 14 files
**Lines Added**: ~2,365 lines
**New Files**: 
- `TranscriptionDatabase.swift` (439 lines)
- `TranscriptionManager.swift` (678 lines)
- `TranscriptionQueue.swift` (~200 lines)
- `AIMagicControlsView.swift` (317 lines)
- `TRANSCRIPTION_DATABASE.md` (282 lines)
- `SQLITE_DATABASE_REPORT.md` (506 lines)

**Dependencies Added**:
- GRDB.swift (SQLite wrapper)

---

## 🚀 Migration & Compatibility

### iOS Version Requirement
- **Minimum**: iOS 26.0+ (for Speech Framework)
- **Feature Availability**: Automatically checks iOS version and Speech Framework availability
- **Graceful Degradation**: Feature is hidden/disabled on unsupported devices

### Database Migration
- **New Database**: Fresh SQLite database created on first use
- **Location**: `Documents/transcription.db`
- **No Migration Needed**: This is a new feature, no existing data to migrate

### Backward Compatibility
- **Existing Books**: Continue to work normally
- **Transcription**: Optional feature - books work fine without transcription
- **Settings**: No changes to existing settings

---

## 🐛 Known Limitations

1. **English Only**: Currently supports English (en-US) transcription only
2. **2-Minute Chunks**: Fixed chunk size of 2 minutes (configurable in code)
3. **iOS 26+ Only**: Requires iOS 26.0 or newer for Speech Framework
4. **Battery Impact**: Transcription is CPU-intensive, power-aware processing helps but may drain battery during long sessions
5. **Storage**: Each transcribed book adds ~2-7 MB of data (for 26-hour book)

---

## 🔮 Future Enhancements

### Planned Features
1. **"What did I miss?" Button**: AI-powered summary of missed content
2. **Multi-language Support**: Support for additional languages beyond English
3. **Configurable Chunk Size**: User preference for transcription chunk size
4. **Offline Transcription**: Ensure transcription works completely offline
5. **Export Transcription**: Export transcribed text as SRT or text file
6. **Search in Transcription**: Search for specific words/phrases in transcribed text
7. **Playback Screen Integration**: Show captions directly on playback screen (not just AI Magic view)

### Technical Improvements
1. **Performance Optimization**: Further optimize database queries for very long books
2. **Memory Management**: Optimize memory usage for large transcription datasets
3. **Error Recovery**: Enhanced error recovery and retry logic
4. **Testing**: Comprehensive unit and integration tests

---

## 📝 Developer Notes

### Key Design Decisions

1. **SQLite over In-Memory**: Chose persistent storage to handle large books and support app restarts
2. **GRDB.swift over SQLite.swift**: Better performance, type safety, and batch operation support
3. **Actor for Queue**: Ensures thread-safe concurrent task management
4. **Windowed Loading**: Prevents UI slowdowns with large transcription datasets
5. **Timestamp Rounding**: Handles transcriber timestamp variations gracefully
6. **Power-Aware Processing**: Balances user experience with battery life

### Code Organization

**Managers**:
- `TranscriptionDatabase`: Data persistence layer
- `TranscriptionManager`: Transcription orchestration
- `TranscriptionQueue`: Task queue management

**Views**:
- `AIMagicControlsView`: Transcription display UI

**Models**:
- `TranscribedSentence`: Sentence data model
- `TranscriptionChunk`: Chunk metadata model

---

## 🙏 Acknowledgments

This feature leverages:
- **iOS 26 Speech Framework**: Apple's new speech recognition API
- **GRDB.swift**: Excellent SQLite wrapper by Gwendal Roué
- **Swift Concurrency**: Modern async/await and actor patterns

---

## 📚 Documentation Updates

The following documentation files have been created/updated:
- `TRANSCRIPTION_DATABASE.md`: Complete database architecture documentation
- `SQLITE_DATABASE_REPORT.md`: Database design decisions and rationale
- `ARCHITECTURE.md`: Updated with new components (see below)
- `README.md`: Updated with transcription feature (see below)

---

**Release Date**: December 15, 2025  
**Version**: Transcription Feature Release  
**Base Commit**: `28503047bbcc5a2d1d22b3f69158d7b75046a601`
