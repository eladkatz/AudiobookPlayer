# Transcription Service Flow Documentation

## Overview

The transcription service transcribes audiobook audio into text sentences with timestamps. It uses a **chapter-based approach**, transcribing entire chapters at a time rather than fixed-size chunks. This provides a simpler, more reliable transcription experience that aligns with how users consume audiobooks.

## Architecture Components

### 1. **TranscriptionManager** (`TranscriptionManager.swift`)
- **Purpose**: Core transcription logic - performs actual speech-to-text conversion
- **Key Methods**:
  - `transcribeChapter(book:chapterID:startTime:endTime:)` - Transcribes an entire chapter
  - `isTranscriberAvailable()` - Checks if SpeechTranscriber API/service is available
  - `loadSentencesForChapter(bookID:chapterID:)` - Loads sentences for a specific chapter
  - `getTranscriptionProgress(bookID:)` - Gets current transcription progress
- **State Tracking**:
  - `currentTranscribingChapterID` - Tracks which chapter is currently being transcribed (for UI display)

### 2. **TranscriptionQueue** (`TranscriptionQueue.swift`)
- **Purpose**: Manages transcription task queue with single-task execution
- **Key Methods**:
  - `enqueueChapter(book:chapter:priority:)` - Adds chapter transcription task to queue
  - `enqueueNextChapter(book:chapter:)` - Queues next chapter for pre-transcription
  - `processNext()` - Processes next task from queue (single task at a time)
  - `executeTask(_ task:)` - Executes transcription task
- **Features**:
  - **Single-Task Execution**: Only one transcription task runs at a time, preventing race conditions
  - **Progress Monitoring**: Monitors transcription progress and cancels if no progress for 30 seconds (60s grace for first sentence)
  - **Retry Logic**: Automatic retries (max 3) with 30-second backoff for failed tasks
  - **Pre-transcription**: Automatically queues next chapter when current chapter starts transcribing

### 3. **TranscriptionDatabase** (`TranscriptionDatabase.swift`)
- **Purpose**: SQLite persistence for transcription data
- **Key Methods**:
  - `isChapterTranscribed(bookID:chapterID:)` - Checks if a chapter is fully transcribed
  - `isChapterTranscribing(bookID:chapterID:)` - Checks if a chapter is currently being transcribed
  - `saveChapterTranscription(bookID:chapterID:sentences:)` - Saves chapter transcription
  - `loadSentencesForChapter(bookID:chapterID:)` - Loads all sentences for a chapter
  - `getTranscriptionProgress(bookID:)` - Returns MAX(end_time) from sentences table

### 4. **AudioManager** (`AudioManager.swift`)
- **Purpose**: Audio playback, chapter management, and transcription triggers
- **Key Methods**:
  - `ensureCurrentChapterTranscribed()` - Ensures current chapter is transcribed (main trigger)
  - `queueNextChapterIfNeeded(book:currentChapter:)` - Queues next chapter for pre-transcription
  - `updateCurrentChapterIndex()` - Updates current chapter based on playback time
  - `play()` - Starts playback and triggers transcription check
  - `seek(to:completion:)` - Seeks to position and triggers transcription check
- **State Tracking**:
  - `chaptersLoaded` - Tracks when chapters are loaded (prevents premature transcription triggers)

### 5. **ChapterParser** (`ChapterParser.swift`)
- **Purpose**: Shared utility for parsing chapters from audiobook files
- **Key Methods**:
  - `parseChapters(from:duration:)` - Parses chapters from AVAsset and duration
- **Used By**:
  - `AudioManager` - For parsing chapters during book load
  - `BookFileManager` - For parsing chapters after import to queue first chapter transcription

### 6. **BookFileManager** (`FileManager.swift`)
- **Purpose**: Manages book file operations and post-import tasks
- **Key Methods**:
  - `importBook(from:)` - Imports M4B file from local storage
  - `importBookFromGoogleDriveM4B(m4bFileID:folderID:)` - Imports book from Google Drive
  - `queueFirstChapterTranscription(for:)` - Queues first chapter transcription after import (iOS 26+)

### 7. **AIMagicControlsView** (`AIMagicControlsView.swift`)
- **Purpose**: UI for displaying transcription captions
- **Key Methods**:
  - `loadSentencesForCurrentChapter()` - Loads sentences for current chapter
  - `updateCurrentSentence(for:)` - Updates highlighted sentence based on playback time
- **Smart Display Logic**:
  - Only shows "Transcribing..." if the current chapter is the one being transcribed
  - Shows transcribed sentences even if next chapter is transcribing in background

## Transcription Flow Sequence

### When User Switches to a Chapter

1. **Chapter Change Detected** → `AudioManager.updateCurrentChapterIndex()` detects chapter change
2. **Chapters Loaded Check** → Verifies `chaptersLoaded == true` before proceeding
3. **Transcription Check** → `ensureCurrentChapterTranscribed()` is called
4. **Availability Check** → `TranscriptionManager.isTranscriberAvailable()`
5. **Database Check** → `TranscriptionDatabase.isChapterTranscribed()` checks if chapter already transcribed
6. **If Not Transcribed**:
   - Wait 500ms settle delay (prevents rapid scrubbing from triggering multiple tasks)
   - Verify still on same chapter (user might have scrubbed away)
   - Enqueue transcription task → `TranscriptionQueue.enqueueChapter()`
   - Queue next chapter → `queueNextChapterIfNeeded()` (pre-transcription)
7. **Queue Processing** → `TranscriptionQueue.processNext()` picks up task
8. **Execute** → `TranscriptionManager.transcribeChapter()` transcribes entire chapter
9. **Save** → `TranscriptionDatabase.saveChapterTranscription()` saves sentences
10. **UI Update** → `AIMagicControlsView` reloads sentences when transcription completes

### When User Starts Playback

1. **Play Button Pressed** → `AudioManager.play()` is called
2. **Chapters Loaded Check** → Verifies `chaptersLoaded == true`
3. **Transcription Check** → `ensureCurrentChapterTranscribed()` is called
4. **Same Flow** → Continues with steps 4-10 from above

### When User Switches to New Book

1. **Book Loads** → `AudioManager.loadBook()` is called
2. **Chapters Loading** → `chaptersLoaded = false`, chapters load asynchronously
3. **Chapters Ready** → `parseChapters()` completes, sets `chaptersLoaded = true`
4. **Transcription Triggered** → `ensureCurrentChapterTranscribed()` is called automatically
5. **Same Flow** → Continues with transcription check and queue processing

### When Book is Imported

1. **Import Completes** → `BookFileManager.importBook()` or `importBookFromGoogleDriveM4B()` returns book
2. **Book Added to Library** → Book is saved to persistence
3. **Background Transcription** → `queueFirstChapterTranscription()` is called in background task
4. **Chapter Parsing** → Chapters are parsed from the book file using `ChapterParser`
5. **First Chapter Check** → Checks if first chapter is already transcribed
6. **Queue Transcription** → If not transcribed, queues first chapter with `.low` priority
7. **User Opens Book** → When user opens the book, first chapter transcription may already be complete or in progress

## Transcription Triggers

### Primary Triggers

1. **Book Import** (`BookFileManager.queueFirstChapterTranscription()`)
   - When a book is successfully imported (local or Google Drive)
   - Automatically queues first chapter transcription with `.low` priority
   - Runs in background, doesn't block import completion
   - Ensures first chapter is ready when user opens the book
   - Skips if transcription is disabled, unavailable, or already transcribed

2. **Chapter Change** (`updateCurrentChapterIndex()`)
   - When playback time moves to a different chapter
   - Triggers `ensureCurrentChapterTranscribed()`
   - Only if `chaptersLoaded == true`

3. **Playback Start** (`play()`)
   - When user presses play button
   - Triggers `ensureCurrentChapterTranscribed()`
   - Handles case where user switches books and hits play without chapter change
   - Only if `chaptersLoaded == true`

4. **Chapters Loaded** (`parseChapters()`)
   - When chapters finish loading after book load
   - Automatically triggers `ensureCurrentChapterTranscribed()`
   - Ensures transcription starts even if user doesn't interact

5. **Manual Chapter Selection** (via `ChaptersListView`)
   - When user selects a chapter from the chapter list
   - Triggers seek, which updates chapter index and triggers transcription

### Debouncing and Settle Delay

- **500ms Settle Delay**: After detecting untranscribed chapter, waits 500ms before enqueueing
  - Prevents rapid scrubbing from creating multiple tasks
  - Verifies user has settled on the chapter
- **Chapter Validation**: After delay, verifies user is still on the same chapter
  - If user moved, cancels transcription task
  - If chapter index updated during load but chapter still exists, proceeds

## Queue Processing

### Single-Task Execution

- **Only one task runs at a time** to prevent race conditions and database conflicts
- When a new chapter is requested:
  - If same chapter is already running, skips enqueueing
  - If different chapter is running, cancels current task and starts new one
  - Ensures user always gets the chapter they're listening to transcribed first

### Task Priority

- **`.high`**: Current chapter (user is actively listening)
- **`.medium`**: Next chapter (pre-transcription for seamless playback)
- **`.low`**: First chapter transcription after import (background, doesn't block user actions)

### Progress Monitoring

- Monitors `TranscriptionManager.currentSentenceCount` every 5 seconds
- **Timeout Logic**:
  - 30 seconds without progress → cancels task and retries
  - 60 seconds grace period for first sentence (allows time for initial processing)
- **Retry Strategy**:
  - Max 3 retries per task
  - 30-second backoff delay between retries
  - Task marked as failed after max retries

### Pre-transcription

- When current chapter starts transcribing, automatically queues next chapter
- **Limitations**:
  - Only queues one chapter ahead (not infinite queue)
  - Only queues when current chapter is the one being played
  - Skips if next chapter is already transcribed or queued

## Database Schema

### Chapter-Based Storage

- **`chapter_transcriptions` table**:
  - `book_id` (UUID)
  - `chapter_id` (UUID)
  - `start_time` (REAL)
  - `end_time` (REAL)
  - `is_complete` (INTEGER) - 1 if fully transcribed, 0 if in progress
  - `transcribed_at` (TEXT) - ISO 8601 timestamp

- **`sentences` table**:
  - `id` (UUID)
  - `book_id` (UUID)
  - `chapter_id` (UUID) - Links to chapter
  - `chunk_id` (TEXT, nullable) - Legacy field, not used in chapter-based approach
  - `text` (TEXT)
  - `start_time` (REAL)
  - `end_time` (REAL)
  - `created_at` (TEXT)

## UI Display Flow

### AIMagicControlsView

1. **View Appears** → `loadInitialSentences()` called
2. **Load Sentences** → `TranscriptionManager.loadSentencesForChapter()` for current chapter
3. **Display Logic**:
   - If transcription disabled → Shows "Transcription is turned off"
   - If loading → Shows "Loading transcription..."
   - If current chapter is transcribing → Shows "Transcribing..."
   - If sentences available → Shows current sentence based on playback time
   - If no sentences → Shows "Not yet transcribed"
4. **Playback Updates** → `updateCurrentSentence(for:)` highlights sentence matching current time
5. **Chapter Changes** → `onChange(currentChapterIndex)` reloads sentences for new chapter
6. **Transcription Completes** → `onChange(isTranscribing)` reloads sentences when transcription finishes

### Smart Display Logic

- **Current Chapter Tracking**: Only shows "Transcribing..." if `currentTranscribingChapterID` matches current chapter ID
- **Background Transcription**: Shows transcribed sentences even if next chapter is transcribing in background
- **Immediate Updates**: Reloads sentences when transcription completes to show new content immediately

## Error Handling

### SpeechTranscriber Unavailable
- `isTranscriberAvailable()` returns `false`
- Transcription check exits early
- No error shown to user (graceful degradation)

### Transcription Failure
- Task times out after 30 seconds without progress
- Automatic retry (max 3 attempts) with 30-second backoff
- After max retries, task is marked as failed
- User can retry by seeking to chapter again

### Chapter Loading Race Condition
- `chaptersLoaded` flag prevents premature transcription triggers
- Transcription waits for chapters to load before starting
- Robust chapter validation handles index updates during load

## Key Timing Details

### Settle Delay
- **500ms** after detecting untranscribed chapter
- Prevents rapid scrubbing from creating multiple tasks
- Verifies user has settled on the chapter

### Progress Timeout
- **30 seconds** without new sentences → timeout
- **60 seconds** grace period for first sentence
- Prevents tasks from hanging indefinitely

### Retry Backoff
- **30 seconds** delay between retry attempts
- **Max 3 retries** per task
- Exponential backoff could be added in future

## Migration from Chunk-Based to Chapter-Based

The system was migrated from a chunk-based approach (2-minute fixed chunks) to a chapter-based approach. Key differences:

- **Old**: Transcribed in 2-minute chunks, detected gaps
- **New**: Transcribes entire chapters, simpler logic
- **Old**: Multiple concurrent tasks
- **New**: Single-task execution with queue
- **Old**: Complex gap detection and chunk boundary calculations
- **New**: Simple chapter-based checks

The database schema supports both approaches for backward compatibility, but new transcriptions use the chapter-based approach exclusively.

## Auto-Transcription on Import

### Overview

To improve user experience, the app automatically queues the first chapter for transcription immediately after a book is imported. This ensures that when users open a newly imported book, the first chapter transcription is either already complete or in progress, eliminating the wait time for the most common use case.

### Implementation Details

**When it happens:**
- After successful import from local files (`importBook(from:)`)
- After successful import from Google Drive (`importBookFromGoogleDriveM4B()`)
- Runs in background with `.utility` priority
- Does not block import completion or UI

**Priority:**
- Uses `.low` priority in TranscriptionQueue
- User-initiated transcriptions (`.high` priority) take precedence
- Ensures background transcription doesn't interfere with active listening

**Checks performed:**
1. Transcription must be enabled (`TranscriptionSettings.shared.isEnabled`)
2. SpeechTranscriber must be available
3. Book must have valid duration
4. First chapter must not already be transcribed
5. First chapter must not already be queued or running

**Error handling:**
- All errors are logged but don't interrupt import flow
- Silent failures - user experience is not impacted
- Transcription will still trigger when user opens the book (fallback behavior)

### User Experience

**Normal flow:**
1. User imports book → Import completes
2. First chapter transcription starts in background (low priority)
3. User opens book → First chapter may already be transcribed
4. If complete: Sentences display immediately
5. If in progress: Shows "Transcribing..." indicator
6. If not started: Falls back to normal transcription trigger

**Benefits:**
- Zero wait time for first chapter in most cases
- Seamless experience for new users
- No UI changes needed - existing UI handles all states
- Background processing doesn't impact app responsiveness

**Edge cases handled:**
- User opens book before transcription starts → Normal trigger takes over
- User opens book while transcription in progress → Shows "Transcribing..." state
- Transcription fails → User can still use book, transcription retries when user opens chapter
- Multiple imports → Single-task execution ensures only one transcription at a time
