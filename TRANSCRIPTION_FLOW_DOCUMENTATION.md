# Transcription Service Flow Documentation

## Overview

The transcription service transcribes audiobook audio into text sentences with timestamps. It works in 2-minute chunks, automatically detecting gaps and transcribing missing segments.

## Architecture Components

### 1. **TranscriptionManager** (`TranscriptionManager.swift`)
- **Purpose**: Core transcription logic - performs actual speech-to-text conversion
- **Key Methods**:
  - `transcribeChunk(book:startTime:)` - Transcribes a 2-minute audio chunk
  - `isTranscriberAvailable()` - Checks if SpeechTranscriber API/service is available
  - `checkIfTranscriptionNeededAtSeekPosition(bookID:seekTime:chunkSize:)` - Determines if transcription needed at position
  - `loadSentencesForDisplay(bookID:startTime:endTime:)` - Loads sentences from database for UI
  - `getTranscriptionProgress(bookID:)` - Gets current transcription progress

### 2. **TranscriptionQueue** (`TranscriptionQueue.swift`)
- **Purpose**: Manages background transcription task queue with priority system
- **Key Methods**:
  - `enqueue(_ task:)` - Adds transcription task to queue
  - `processNext()` - Processes next task from queue
  - `executeTask(_ task:)` - Executes transcription task
  - `detectTranscriptionGaps(books:currentBookID:)` - Detects missing transcription chunks (REMOVED from startup)

### 3. **TranscriptionDatabase** (`TranscriptionDatabase.swift`)
- **Purpose**: SQLite persistence for transcription data
- **Key Methods**:
  - `getTranscriptionProgress(bookID:)` - Returns MAX(end_time) from sentences table
  - `getChunkCount(bookID:)` - Returns count of transcription chunks
  - `loadSentences(bookID:startTime:endTime:)` - Loads sentences in time range
  - `insertChunk(_ chunk:)` - Saves transcription chunk

### 4. **AudioManager** (`AudioManager.swift`)
- **Purpose**: Audio playback and seek handling
- **Key Methods**:
  - `checkAndTriggerTranscriptionForSeek(time:)` - Checks and triggers transcription after seek
  - `seek(to:completion:)` - Seeks to position and triggers transcription check

### 5. **AIMagicControlsView** (`AIMagicControlsView.swift`)
- **Purpose**: UI for displaying transcription
- **Key Methods**:
  - `loadInitialSentences()` - Loads sentences when view appears
  - `handleBookChange(newID:)` - Handles book changes

## Transcription Flow Sequence

### Sequence Diagram

## Transcription Trigger Flow

### When Book Loads (App Startup)

1. **App Startup** → `AudioManager.loadBook(book)`
2. **Player Ready** → `player.seek(to: savedPosition)` (e.g., 32:10)
3. **Seek Completes** → `checkAndTriggerTranscriptionForSeek(time: 32:10)`
4. **Wait 1 second** (debounce delay)
5. **Check Availability** → `TranscriptionManager.isTranscriberAvailable()`
   - Returns `true` if SpeechTranscriber API is available
   - Returns `false` if not available (simulator, old iOS, etc.)
6. **If Available** → `checkIfTranscriptionNeededAtSeekPosition(bookID, seekTime: 32:10)`
   - Queries database: `getTranscriptionProgress(bookID)` → Returns max transcribed time (e.g., 20:00)
   - Calculates: `progress (20:00) < seekTime (32:10) + threshold (60s)` → TRUE
   - Returns chunk start: `floor(32:10 / 2:00) * 2:00` = 32:00
7. **Enqueue Task** → `TranscriptionQueue.enqueue(task)` with chunk start time 32:00
8. **Queue Processes** → `TranscriptionQueue.processNext()` picks up task
9. **Execute** → `TranscriptionManager.transcribeChunk(book, startTime: 32:00)`
10. **Save** → `TranscriptionDatabase.insertChunk(chunk)` saves sentences

### When User Seeks Manually

Same flow as above, but triggered by:
- User drags scrubber
- User presses skip forward/backward
- User navigates to chapter

### UI Display Flow (Separate)

1. **UI Appears** → `AIMagicControlsView.loadInitialSentences()`
2. **Query Database** → `loadSentencesForDisplay(bookID, startTime: 32:10-30s, endTime: 32:10+75s)`
3. **If No Sentences** → Fallback: Load from beginning (00:00) up to progress + 60s
4. **Display** → Shows sentences in UI

## Answers to Key Questions

### Q1: What triggers `checkIfTranscriptionNeededAtSeekPosition()`?

**Answer**: It's called from `AudioManager.checkAndTriggerTranscriptionForSeek(time:)`, which is triggered by:

1. **Book loads** → When player becomes ready and seeks to saved position
2. **User seeks manually** → After any `seek(to:completion:)` completes
3. **Skip buttons** → `skipForward()` / `skipBackward()` call `seek()`
4. **Chapter navigation** → `nextChapter()` / `previousChapter()` call `seek()`
5. **Playback starts/resumes** → `AudioManager.play()` calls `checkAndTriggerTranscriptionForSeek()`
6. **AI Magic view opens** → `AIMagicControlsView.loadInitialSentences()` calls `checkAndTriggerTranscriptionForSeek()` if no sentences found

**Code Path**:
```
AudioManager.seek(to:completion:) OR AudioManager.play() OR AIMagicControlsView.loadInitialSentences()
  → checkAndTriggerTranscriptionForSeek(time: position)
    → (after 1 second debounce)
      → TranscriptionManager.isTranscriberAvailable()
      → TranscriptionManager.checkIfTranscriptionNeededAtSeekPosition()
```

### Q2: What does `isTranscriberAvailable()` do?

**Answer**: Checks if the **SpeechTranscriber API/service is available** on the device.

**What it does**:
1. Checks `SpeechTranscriber.isAvailable` (runtime check)
2. Checks if English locale (`en-US`) is in `SpeechTranscriber.supportedLocales`
3. Returns `true` if both pass, `false` otherwise
4. Results are cached after first check for performance

**Note**: This checks API availability, not whether transcription exists for a time. To check if transcription exists, use `checkIfTranscriptionNeededAtSeekPosition()`.

### Q3: When does transcription actually start?

**Answer**: Transcription starts when:

1. **App startup** → Book loads, seeks to saved position → Triggers check
2. **User seeks** → Manual seek → Triggers check
3. **Skip buttons** → Skip forward/back → Triggers check
4. **Chapter navigation** → Next/previous chapter → Triggers check
5. **Playback starts/resumes** → `AudioManager.play()` → Triggers check
6. **AI Magic view opens** → If no sentences found at current position → Triggers check

**Conditions for transcription to start**:
- A seek completes OR playback starts OR AI Magic view opens
- The position needs transcription (progress < seekTime + threshold)
- SpeechTranscriber is available (`isTranscriberAvailable()` returns `true`)

**What does NOT trigger transcription**:
- Time advancing during playback (only on seek/play start)
- App sitting idle

### Q4: Why does the UI show 00:00 when user is at 32:10?

**Answer**: This is the **fallback behavior** in `AIMagicControlsView`:

1. UI tries to load sentences at current position (32:10)
2. No sentences found (transcription hasn't started yet or isn't complete)
3. Fallback logic kicks in: `if progress > 0, load from 00:00 to progress + 60s`
4. If `progress = 0` (no transcription exists), fallback doesn't run → Shows empty state
5. If `progress > 0` but no sentences at 32:10, fallback loads from 00:00 → Shows 00:00

**Note**: If no sentences are found, the view now automatically triggers a transcription check at the current position.

## Trigger Points

### 1. **App Startup / Book Load**
**Location**: `AudioManager.loadBook()` → `readyToPlay` status observer

**Flow**:
1. Book loads, player becomes ready
2. If `book.currentPosition > 0`, seek to saved position
3. In seek completion handler: `checkAndTriggerTranscriptionForSeek(time: savedPosition)`
4. If `book.currentPosition == 0`, directly call `checkAndTriggerTranscriptionForSeek(time: 0)`

**Code Path**:
```
AudioManager.loadBook()
  → playerItem.observe(.status)
    → case .readyToPlay
      → player.seek(to: book.currentPosition)
        → completionHandler
          → checkAndTriggerTranscriptionForSeek(time: savedPosition)
```

### 2. **User Seeks** (Manual Seek)
**Location**: `AudioManager.seek(to:completion:)`

**Flow**:
1. User seeks to new position (scrubber, skip buttons, chapter navigation)
2. Seek completes successfully
3. `checkAndTriggerTranscriptionForSeek(time: newPosition)` called
4. Debounced 1 second, then checks if transcription needed

**Code Path**:
```
AudioManager.seek(to:completion:)
  → player.seek(to: cmTime)
    → completionHandler
      → checkAndTriggerTranscriptionForSeek(time: time)
```

### 3. **Skip Forward/Backward**
**Location**: `AudioManager.skipForward()` / `skipBackward()`

**Flow**:
1. User presses skip buttons
2. Calls `seek(to: newTime)` which triggers transcription check

**Code Path**:
```
AudioManager.skipForward(interval:)
  → seek(to: newTime)
    → (same as manual seek flow)
```

### 4. **Chapter Navigation**
**Location**: `AudioManager.nextChapter()` / `previousChapter()`

**Flow**:
1. User navigates to next/previous chapter
2. Calls `seek(to: chapter.startTime)` which triggers transcription check

**Code Path**:
```
AudioManager.nextChapter()
  → seek(to: nextChapter.startTime)
    → (same as manual seek flow)
```

### 5. **AIMagicControlsView Load** (Display Only)
**Location**: `AIMagicControlsView.task` / `onAppear`

**Flow**:
1. User opens AI Magic view
2. `loadInitialSentences()` called
3. Loads sentences from database for current time window
4. **Does NOT trigger transcription** - only displays existing data

**Code Path**:
```
AIMagicControlsView.task
  → loadInitialSentences()
    → transcriptionManager.loadSentencesForDisplay()
      → database.loadSentences()
        → Update UI with sentences
```

## Transcription Decision Logic

### `checkIfTranscriptionNeededAtSeekPosition()`

**Location**: `TranscriptionManager.checkIfTranscriptionNeededAtSeekPosition()`

**Logic**:
```swift
let progress = database.getTranscriptionProgress(bookID)  // MAX(end_time) from sentences
let threshold = chunkSize / 2.0  // 60 seconds (half of 2-minute chunk)
let required = seekTime + threshold

if progress < required {
    // Calculate chunk boundary (rounds down to 2-minute boundary)
    let chunkStartTime = floor(seekTime / chunkSize) * chunkSize
    return chunkStartTime  // Transcription needed
} else {
    return nil  // Already covered
}
```

**Examples**:
- User at 32:10 (1930s), progress = 0:00 (0s) → Returns 1920s (32:00 chunk start)
- User at 32:10 (1930s), progress = 30:00 (1800s) → Returns 1920s (32:00 chunk start)
- User at 32:10 (1930s), progress = 33:00 (1980s) → Returns nil (already covered)

## Queue Processing

### Task Priority
- **`.high`**: Current book's transcription needs (user is actively listening)
- **`.medium`**: Books in progress with gaps
- **`.low`**: Books not yet started

### Processing Flow
1. `TranscriptionQueue.init()` starts `startProcessingTask()` in background
2. `processNext()` runs every 1 second
3. Checks if `runningTasks.count < maxConcurrentTasks` (max 5)
4. Gets highest priority task from queue
5. Moves to `runningTasks`
6. Calls `executeTask()` which calls `TranscriptionManager.transcribeChunk()`
7. When complete, removes from `runningTasks`

## Database Progress Tracking

### `getTranscriptionProgress(bookID:)`
**Query**: `SELECT MAX(end_time) FROM sentences WHERE book_id = ?`

**Returns**: The latest `end_time` of any sentence for the book, or `0.0` if no sentences exist.

**Important**: This represents the **furthest point** that has been transcribed, not necessarily contiguous coverage.

## Gap Detection (Currently Disabled)

**Status**: Removed from startup to improve performance

**Previous Behavior** (when enabled):
- Ran 15 seconds after app start
- Checked all books for gaps
- Queued tasks for missing chunks

**Current Behavior**:
- Gap detection removed from startup
- Transcription only triggered by:
  1. User seeks to untranscribed position
  2. User uses skip controls
  3. Book loads at untranscribed position

## Key Timing Details

### Debouncing
- `checkAndTriggerTranscriptionForSeek()` waits 1 second after seek before checking
- Prevents excessive checks during rapid seeks

### Chunk Size
- Fixed at **120 seconds (2 minutes)**
- Chunk boundaries: 0:00, 2:00, 4:00, 6:00, etc.
- `floor(seekTime / 120.0) * 120.0` calculates chunk start

### Threshold
- **60 seconds** (half chunk size)
- Transcription triggered if `progress < seekTime + 60s`
- Ensures transcription starts before user reaches untranscribed area

## Error Handling

### SpeechTranscriber Unavailable
- `isTranscriptionAvailable()` returns `false`
- Transcription check exits early
- No error shown to user (graceful degradation)

### Transcription Failure
- `transcribeChunk()` catches errors
- Updates `errorMessage` in TranscriptionManager
- Task removed from queue
- User can retry by seeking again

## UI Display Flow

### AIMagicControlsView
1. **onAppear**: Calls `loadInitialSentences()`
2. **loadInitialSentences()**:
   - Calculates window: `[currentTime - 30s, currentTime + 75s]`
   - Calls `loadSentencesForDisplay(bookID, startTime, endTime)`
   - If no sentences found, tries fallback: load from beginning up to `progress + 60s`
3. **onChange(currentTime)**: Updates highlighted sentence
4. **onChange(currentBook)**: Reloads sentences for new book

### Fallback Behavior
If no sentences in current window:
- Tries loading from beginning (0s) up to `progress + 60s`
- This is why user might see 00:00 when at 32:10 - it's showing the fallback content


