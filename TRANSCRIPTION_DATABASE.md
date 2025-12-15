# Transcription Database Architecture

## Overview

The transcription feature uses SQLite to persist transcribed sentences and chunk metadata. The database is managed through **GRDB.swift**, a Swift wrapper that provides type-safe, performant database operations.

## Why GRDB.swift?

**Selected:** GRDB.swift

**Reasons:**
- **Type Safety**: Swift Codable integration, compile-time query checking
- **Performance**: Optimized for batch operations with built-in connection pooling
- **Concurrency**: Thread-safe with proper isolation levels via `DatabaseQueue`
- **Features**: Built-in support for transactions, prepared statements, and efficient batch inserts
- **Documentation**: Excellent docs and active maintenance
- **Reliability**: Handles string binding and UUID storage correctly, avoiding low-level C API pitfalls

**Alternative Considered:** SQLite.swift - Simpler but lacks advanced features like migrations and has less optimized batch operations.

## Database Schema

### Tables

#### `sentences` Table

Stores individual transcribed sentences with absolute timestamps.

```sql
CREATE TABLE sentences (
    id TEXT PRIMARY KEY,                    -- UUID string
    book_id TEXT NOT NULL,                  -- UUID string
    text TEXT NOT NULL,                     -- Sentence text
    start_time REAL NOT NULL,               -- Absolute time in book (seconds, rounded to 0.1s)
    end_time REAL NOT NULL,                 -- Absolute time in book (seconds, rounded to 0.1s)
    chunk_id TEXT NOT NULL,                 -- UUID of parent chunk
    created_at REAL NOT NULL                -- Timestamp when inserted
);
```

**Purpose:** Individual transcribed sentences with absolute timestamps from the transcriber.

**Indexes:**
- `idx_sentences_book_time` on `(book_id, start_time)` - Primary access pattern for loading sentences in time range
- `idx_sentences_book_end_time` on `(book_id, end_time)` - For queries filtering by end time

#### `chunks` Table

Stores metadata for each transcription chunk (typically 2-minute segments).

```sql
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,                    -- UUID string
    book_id TEXT NOT NULL,                  -- UUID string
    start_time REAL NOT NULL,               -- Chunk start time (seconds, rounded to 0.1s)
    end_time REAL NOT NULL,                 -- Chunk end time (seconds, rounded to 0.1s)
    created_at REAL NOT NULL,               -- Timestamp when chunk was transcribed
    is_complete INTEGER NOT NULL DEFAULT 1  -- Whether chunk transcription is complete
);
```

**Purpose:** Metadata for each transcription chunk. Tracks what has been transcribed and enables efficient seeking.

**Indexes:**
- `idx_chunks_book_time` on `(book_id, start_time)` - For queries filtering by start time
- `idx_chunks_book_end_time` on `(book_id, end_time)` - Critical for finding next transcription start time

## Timestamp Strategy

### Source
Timestamps come from `AttributedString.runs` with `audioTimeRange` attribute from `SpeechTranscriber`. `CMTimeGetSeconds()` returns `TimeInterval` (Double), so no conversion needed.

### Storage
- **Format**: Stored as `REAL` (Double) representing seconds from book start (0:00)
- **Precision**: Rounded to **0.1s precision** when storing: `round(timestamp * 10) / 10.0`
- **Absolute Timestamps**: Each sentence stores its absolute position in the book timeline
- **Offset Application**: When transcribing a 2-minute segment starting at 120s, add 120s to all sentence timestamps, then round

### Why Round to 0.1s?
- Transcriber may return slightly different timestamps (±0.3s) for the same content
- Rounding normalizes these variations
- 0.1s precision is sufficient for seeking and highlighting (100ms granularity)
- Prevents duplicate detection issues from timestamp variations

### Why REAL not INTEGER?
- Speech API provides sub-second precision (milliseconds)
- Enables precise seeking and highlighting even with rounding
- REAL is efficient for range queries in SQLite

## Data Operations

### Inserting Transcription Chunks

**Process:**
1. Begin transaction (GRDB handles this automatically)
2. Insert chunk metadata into `chunks` table using `INSERT OR REPLACE`
3. Delete existing sentences in the chunk's time range (handles re-transcription)
4. Insert all sentences from the chunk using `INSERT OR REPLACE` (handles duplicates)
5. Commit transaction

**Implementation:**
```swift
try dbQueue.write { db in
    // Insert chunk metadata
    try db.execute(
        sql: "INSERT OR REPLACE INTO chunks ...",
        arguments: [...]
    )
    
    // Delete existing sentences in time range
    try db.execute(
        sql: "DELETE FROM sentences WHERE book_id = ? AND start_time >= ? AND start_time < ?",
        arguments: [bookIDString, chunk.startTime, chunk.endTime]
    )
    
    // Insert sentences
    for sentence in chunk.sentences {
        try db.execute(
            sql: "INSERT OR REPLACE INTO sentences ...",
            arguments: [...]
        )
    }
}
```

**Conflict Resolution:**
- Uses `INSERT OR REPLACE` at database level
- Primary key is `id` (UUID), so duplicates are automatically replaced
- No code-level protection needed - database handles it

### Loading Sentences

**Query Pattern:**
```swift
SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
FROM sentences
WHERE book_id = ? AND start_time >= ? AND start_time < ?
ORDER BY start_time ASC
```

**Performance:**
- Index on `(book_id, start_time)` makes this O(log n + m) where m is result size
- Efficient for loading sentences in time range for display
- Supports pagination by adjusting time range

### Finding Next Transcription Start Time

**Query:**
```swift
SELECT MAX(end_time) as max_end_time
FROM chunks
WHERE book_id = ?
```

**Purpose:** Determines where to start the next 2-minute transcription chunk.

**Logic:**
- If no chunks exist, start from 0:00
- Otherwise, start from the latest chunk's `end_time`
- Enables incremental transcription workflow

### Finding Sentence at Playback Position

**Query:**
```swift
SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
FROM sentences
WHERE book_id = ? AND start_time <= ? AND end_time > ?
ORDER BY start_time DESC
LIMIT 1
```

**Purpose:** Finds the sentence currently being spoken for playback highlighting.

## Sentence-to-Chunk Assignment

**Strategy:** Assign sentence to the chunk where it **ends**, not where it starts.

**Example:**
- Chunk A: 0:00-2:00 (120s)
- Chunk B: 2:00-4:00 (240s)
- Sentence starts at 1:59 (119s) and ends at 2:02 (122s) → **Assign to Chunk B** (where it ends)

**Rationale:**
- Ensures no sentence extends outside its assigned chunk's boundaries
- Simplifies chunk management - each chunk contains complete sentences
- No `is_incomplete` flag needed

## Performance Considerations

### Expected Data Volume
- 26-hour book ≈ 10,000-15,000 sentences
- Each sentence: ~50-200 characters text + metadata ≈ 200-500 bytes
- Total per book: ~2-7 MB of data
- Index overhead: ~20-30% additional

### SQLite Performance
- Batch insert of 50 sentences: <10ms
- Range query for 200 sentences: <5ms (with proper index)
- MAX aggregation: <1ms (indexed)

### Scaling
- SQLite handles millions of rows efficiently
- Indexes keep queries fast even with 100,000+ sentences
- No need for sharding or partitioning at expected volumes

## Implementation Details

### Database Location
- **Path**: `Documents/transcription.db`
- **Format**: SQLite 3 database file
- **Access**: Thread-safe via GRDB's `DatabaseQueue`

### Thread Safety
- **Read Operations**: Use `dbQueue.read { db in ... }` - allows concurrent reads
- **Write Operations**: Use `dbQueue.write { db in ... }` - serializes writes
- **Thread Isolation**: GRDB ensures proper isolation levels

### Error Handling
- Database initialization failures trigger recreation
- Corrupted databases are automatically recreated
- All operations wrapped in try-catch with appropriate error propagation

## API Reference

### `TranscriptionDatabase`

**Methods:**

- `loadSentences(bookID:startTime:endTime:)` - Load sentences in time range
- `findSentence(bookID:atTime:)` - Find sentence at specific playback time
- `insertChunk(_:)` - Insert transcription chunk with all sentences
- `getTranscriptionProgress(bookID:)` - Get latest transcribed time
- `getNextTranscriptionStartTime(bookID:)` - Get next chunk start time for incremental transcription
- `getChunkCount(bookID:)` - Get number of transcribed chunks
- `deleteTranscription(bookID:)` - Delete all transcription data for a book
- `clearTranscription(bookID:)` - Alias for `deleteTranscription`

## Current Status

### ✅ Completed
- Database schema design and implementation
- GRDB.swift integration
- Basic CRUD operations (insert, read, delete)
- Index optimization for time-based queries
- Thread-safe database access

### 🔄 Next Steps

1. **Testing & Verification**
   - Test end-to-end transcription flow
   - Verify UUID storage (no empty IDs)
   - Verify timestamp accuracy
   - Test data retrieval and display

2. **Automation**
   - Implement "transcribe as needed" trigger (when buffer < 1.25 minutes)
   - Add progress tracking UI
   - Handle seeking to untranscribed regions

3. **Playback Synchronization**
   - Highlight current sentence during playback
   - Auto-scroll to current sentence in UI

4. **Edge Cases**
   - Handle database corruption gracefully
   - Handle re-transcription of same chunks
   - Handle seeking to gaps in transcription

## Migration Notes

This implementation replaces any previous database work. The database file is created fresh on first use. If migrating from a previous implementation:

1. Old database files are not automatically migrated
2. Users will need to re-transcribe if switching implementations
3. Database location: `Documents/transcription.db`

## References

- [GRDB.swift Documentation](https://github.com/groue/GRDB.swift)
- [SQLite Documentation](https://www.sqlite.org/docs.html)
- Original Plan: `/Users/eladkatz/.cursor/plans/sqlite_wrapper_migration_plan_6ad4d8c0.plan.md`
