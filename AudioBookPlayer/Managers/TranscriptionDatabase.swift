import Foundation
import GRDB

@available(iOS 26.0, *)
class TranscriptionDatabase: @unchecked Sendable {
    static let shared = TranscriptionDatabase()
    
    private var dbQueue: DatabaseQueue?
    private var initializationTask: Task<Void, Never>?
    private let initializationLock = NSLock()
    private var isInitialized = false
    
    private init() {
        // Initialize database asynchronously to avoid blocking
        initializationTask = Task.detached(priority: .utility) {
            await self.setupDatabase()
        }
    }
    
    // MARK: - Database Setup
    
    private func setupDatabase() async {
        // Run database setup on background thread to avoid blocking
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let fileURL = self.databaseURL()
        
        // Create directory if needed
        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        do {
            // Open or create database
                    let queue = try DatabaseQueue(path: fileURL.path)
            
                    // Create tables (synchronous but on background thread)
                    try queue.write { db in
                        try self.createTables(db: db)
            }
                    
                    // Set dbQueue only after successful initialization
                    self.initializationLock.lock()
                    self.dbQueue = queue
                    self.isInitialized = true
                    self.initializationLock.unlock()
            
            print("✅ [TranscriptionDatabase] Database initialized successfully")
                    continuation.resume()
        } catch {
            print("❌ [TranscriptionDatabase] Failed to setup database: \(error)")
            // Try to recreate if setup fails
            try? FileManager.default.removeItem(at: fileURL)
            do {
                        let queue = try DatabaseQueue(path: fileURL.path)
                        try queue.write { db in
                            try self.createTables(db: db)
                }
                        
                        self.initializationLock.lock()
                        self.dbQueue = queue
                        self.isInitialized = true
                        self.initializationLock.unlock()
                        
                print("✅ [TranscriptionDatabase] Database recreated successfully")
                        continuation.resume()
            } catch {
                print("❌ [TranscriptionDatabase] Failed to recreate database: \(error)")
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // Wait for initialization to complete before accessing database
    private func ensureInitialized() async {
        if isInitialized {
            return
        }
        
        // Wait for initialization task to complete
        await initializationTask?.value
    }
    
    private func databaseURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("transcription.db")
    }
    
    private func createTables(db: Database) throws {
        // Create sentences table (chunk_id is nullable for chapter-based transcription)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS sentences (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                text TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                chunk_id TEXT,
                created_at REAL NOT NULL
            );
        """)
        
        // Migration: Check existing table structure and migrate if needed
        var tableExists = false
        var hasChapterId = false
        var chunkIdIsNullable = false
        do {
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(sentences)")
            tableExists = !columns.isEmpty
            for row in columns {
                if let name = row["name"] as String? {
                    if name == "chapter_id" {
                        hasChapterId = true
                    }
                    if name == "chunk_id" {
                        // Check if chunk_id is nullable (notnull = 0 means nullable)
                        if let notnull = row["notnull"] as Int64?, notnull == 0 {
                            chunkIdIsNullable = true
                        }
                    }
                }
            }
        } catch {
            // Table might not exist yet, that's okay
            print("ℹ️ [TranscriptionDatabase] Could not check table info: \(error)")
        }
        
        // Migrate chunk_id to nullable if it's currently NOT NULL
        // SQLite doesn't support ALTER COLUMN, so we need to recreate the table
        // Only migrate if table exists and chunk_id is NOT NULL
        if tableExists && !chunkIdIsNullable && hasChapterId {
            // Table exists and chunk_id is NOT NULL - need to migrate
            print("🔄 [TranscriptionDatabase] Migrating sentences table to make chunk_id nullable...")
            do {
                // Create temporary table with new schema
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS sentences_new (
                        id TEXT PRIMARY KEY,
                        book_id TEXT NOT NULL,
                        text TEXT NOT NULL,
                        start_time REAL NOT NULL,
                        end_time REAL NOT NULL,
                        chunk_id TEXT,
                        chapter_id TEXT,
                        created_at REAL NOT NULL
                    );
                """)
                
                // Copy data from old table to new table
                try db.execute(sql: """
                    INSERT INTO sentences_new 
                    (id, book_id, text, start_time, end_time, chunk_id, chapter_id, created_at)
                    SELECT id, book_id, text, start_time, end_time, chunk_id, chapter_id, created_at
                    FROM sentences;
                """)
                
                // Drop old table
                try db.execute(sql: "DROP TABLE sentences;")
                
                // Rename new table
                try db.execute(sql: "ALTER TABLE sentences_new RENAME TO sentences;")
                
                // Recreate indexes
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_sentences_book_time 
                    ON sentences(book_id, start_time);
                """)
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_sentences_book_end_time 
                    ON sentences(book_id, end_time);
                """)
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_sentences_chapter 
                    ON sentences(book_id, chapter_id);
                """)
                
                print("✅ [TranscriptionDatabase] Successfully migrated sentences table")
            } catch {
                print("❌ [TranscriptionDatabase] Failed to migrate sentences table: \(error)")
                // If migration fails, we'll try to continue - new inserts may fail but old data is preserved
            }
        } else if tableExists && !chunkIdIsNullable {
            // Table exists but no chapter_id yet - simpler migration
            print("🔄 [TranscriptionDatabase] Migrating sentences table to make chunk_id nullable (no chapter_id yet)...")
            do {
                // Create temporary table with new schema
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS sentences_new (
                        id TEXT PRIMARY KEY,
                        book_id TEXT NOT NULL,
                        text TEXT NOT NULL,
                        start_time REAL NOT NULL,
                        end_time REAL NOT NULL,
                        chunk_id TEXT,
                        chapter_id TEXT,
                        created_at REAL NOT NULL
                    );
                """)
                
                // Copy data from old table to new table
                try db.execute(sql: """
                    INSERT INTO sentences_new 
                    (id, book_id, text, start_time, end_time, chunk_id, created_at)
                    SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
                    FROM sentences;
                """)
                
                // Drop old table
                try db.execute(sql: "DROP TABLE sentences;")
                
                // Rename new table
                try db.execute(sql: "ALTER TABLE sentences_new RENAME TO sentences;")
                
                // Recreate indexes
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_sentences_book_time 
                    ON sentences(book_id, start_time);
                """)
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_sentences_book_end_time 
                    ON sentences(book_id, end_time);
                """)
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_sentences_chapter 
                    ON sentences(book_id, chapter_id);
                """)
                
                print("✅ [TranscriptionDatabase] Successfully migrated sentences table")
            } catch {
                print("❌ [TranscriptionDatabase] Failed to migrate sentences table: \(error)")
            }
        }
        
        // Add chapter_id column if it doesn't exist (migration)
        if !hasChapterId {
            do {
                try db.execute(sql: """
                    ALTER TABLE sentences ADD COLUMN chapter_id TEXT;
                """)
                print("✅ [TranscriptionDatabase] Added chapter_id column to sentences table")
            } catch {
                // Column might already exist or table might not exist yet, ignore error
                print("⚠️ [TranscriptionDatabase] Could not add chapter_id column (might already exist): \(error)")
            }
        } else {
            print("ℹ️ [TranscriptionDatabase] chapter_id column already exists")
        }
        
        // Create chunks table (keep for migration)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                created_at REAL NOT NULL,
                is_complete INTEGER NOT NULL DEFAULT 1
            );
        """)
        
        // Create chapter_transcriptions table
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS chapter_transcriptions (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                chapter_id TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                is_complete INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                UNIQUE(book_id, chapter_id)
            );
        """)
        
        // Create indexes for efficient queries
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_sentences_book_time 
            ON sentences(book_id, start_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_sentences_book_end_time 
            ON sentences(book_id, end_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_sentences_chapter 
            ON sentences(book_id, chapter_id);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chunks_book_time 
            ON chunks(book_id, start_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chunks_book_end_time 
            ON chunks(book_id, end_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chapter_transcriptions_book_chapter 
            ON chapter_transcriptions(book_id, chapter_id);
        """)
        
        print("✅ [TranscriptionDatabase] Tables and indexes created")
    }
    
    // MARK: - Public Methods
    
    func loadSentences(
        bookID: UUID,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async -> [TranscribedSentence] {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            print("❌ [TranscriptionDatabase] Database not initialized")
            return []
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let sentences = try dbQueue.read { db -> [TranscribedSentence] in
                    let bookIDString = bookID.uuidString
                    print("💾 [TranscriptionDatabase] Loading sentences: bookID=\(bookIDString), range=\(startTime)s - \(endTime)s")
                    
                    let rows = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
                            FROM sentences
                            WHERE book_id = ? AND start_time >= ? AND start_time < ?
                            ORDER BY start_time ASC
                        """,
                        arguments: [bookIDString, startTime, endTime]
                    )
                    
                    let sentences = rows.compactMap { row -> TranscribedSentence? in
                        guard let idString = row["id"] as String?,
                              let id = UUID(uuidString: idString),
                              let text = row["text"] as String?,
                              let startTime = row["start_time"] as Double?,
                              let endTime = row["end_time"] as Double? else {
                            return nil
                        }
                        return TranscribedSentence(
                            id: id,
                            text: text,
                            startTime: startTime,
                            endTime: endTime
                        )
                    }
                    
                    print("💾 [TranscriptionDatabase] Loaded \(sentences.count) sentences")
                    return sentences
                }
                continuation.resume(returning: sentences)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to load sentences: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    func findSentence(bookID: UUID, atTime: TimeInterval) async -> TranscribedSentence? {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let sentence = try dbQueue.read { db -> TranscribedSentence? in
                    let bookIDString = bookID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
                            FROM sentences
                            WHERE book_id = ? AND start_time <= ? AND end_time > ?
                            ORDER BY start_time DESC
                            LIMIT 1
                        """,
                        arguments: [bookIDString, atTime, atTime]
                    )
                    
                    guard let row = row,
                          let idString = row["id"] as String?,
                          let id = UUID(uuidString: idString),
                          let text = row["text"] as String?,
                          let startTime = row["start_time"] as Double?,
                          let endTime = row["end_time"] as Double? else {
                        return nil
                    }
                    
                    return TranscribedSentence(
                        id: id,
                        text: text,
                        startTime: startTime,
                        endTime: endTime
                    )
                }
                continuation.resume(returning: sentence)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to find sentence: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    func insertChunk(_ chunk: TranscriptionChunk) async throws {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            throw DatabaseError.databaseNotInitialized
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = chunk.bookID.uuidString
                    let chunkIDString = chunk.id.uuidString
                    let createdAt = chunk.transcribedAt.timeIntervalSince1970
                    
                    print("💾 [TranscriptionDatabase] Inserting chunk: \(chunkIDString), \(chunk.sentences.count) sentences, range: \(chunk.startTime)s - \(chunk.endTime)s")
                    
                    // Insert chunk metadata
                    try db.execute(
                        sql: """
                            INSERT OR REPLACE INTO chunks (id, book_id, start_time, end_time, created_at, is_complete)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            chunkIDString,
                            bookIDString,
                            chunk.startTime,
                            chunk.endTime,
                            createdAt,
                            chunk.isComplete ? 1 : 0
                        ]
                    )
                    print("✅ [TranscriptionDatabase] Chunk metadata inserted")
                    
                    // Delete existing sentences in this time range
                    try db.execute(
                        sql: """
                            DELETE FROM sentences
                            WHERE book_id = ? AND start_time >= ? AND start_time < ?
                        """,
                        arguments: [bookIDString, chunk.startTime, chunk.endTime]
                    )
                    print("💾 [TranscriptionDatabase] Deleted existing sentences in time range")
                    
                    // Insert sentences
                    var insertedCount = 0
                    for sentence in chunk.sentences {
                        let sentenceIDString = sentence.id.uuidString
                        
                        try db.execute(
                            sql: """
                                INSERT OR REPLACE INTO sentences 
                                (id, book_id, text, start_time, end_time, chunk_id, created_at)
                                VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                            arguments: [
                                sentenceIDString,
                                bookIDString,
                                sentence.text,
                                sentence.startTime,
                                sentence.endTime,
                                chunkIDString,
                                createdAt
                            ]
                        )
                        insertedCount += 1
                    }
                    
                    print("✅ [TranscriptionDatabase] Inserted \(insertedCount) sentences successfully")
                    continuation.resume()
                }
            } catch {
                print("❌ [TranscriptionDatabase] Failed to insert chunk: \(error)")
                continuation.resume(throwing: DatabaseError.insertFailed(error.localizedDescription))
            }
        }
    }
    
    func getTranscriptionProgress(bookID: UUID) async -> TimeInterval {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return 0.0
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let progress = try dbQueue.read { db -> TimeInterval in
                    let bookIDString = bookID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT MAX(end_time) as max_time
                            FROM sentences
                            WHERE book_id = ?
                        """,
                        arguments: [bookIDString]
                    )
                    
                    return (row?["max_time"] as Double?) ?? 0.0
                }
                continuation.resume(returning: progress)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get progress: \(error)")
                continuation.resume(returning: 0.0)
            }
        }
    }
    
    func getNextTranscriptionStartTime(bookID: UUID) async -> TimeInterval {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return 0.0
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let startTime = try dbQueue.read { db -> TimeInterval in
                    let bookIDString = bookID.uuidString
                    
                    // Find the latest chunk end time
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT MAX(end_time) as max_end_time
                            FROM chunks
                            WHERE book_id = ?
                        """,
                        arguments: [bookIDString]
                    )
                    
                    if let maxEndTime = row?["max_end_time"] as Double? {
                        return maxEndTime
                    }
                    
                    return 0.0
                }
                
                if startTime == 0.0 {
                    print("💾 [TranscriptionDatabase] No existing chunks, starting from 0:00")
                } else {
                    print("💾 [TranscriptionDatabase] Next transcription start time: \(startTime)s")
                }
                
                continuation.resume(returning: startTime)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get next start time: \(error)")
                continuation.resume(returning: 0.0)
            }
        }
    }
    
    func getChunkCount(bookID: UUID) async -> Int {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return 0
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let count = try dbQueue.read { db -> Int in
                    let bookIDString = bookID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*) as count
                            FROM chunks
                            WHERE book_id = ?
                        """,
                        arguments: [bookIDString]
                    )
                    
                    return Int((row?["count"] as Int64?) ?? 0)
                }
                continuation.resume(returning: count)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get chunk count: \(error)")
                continuation.resume(returning: 0)
            }
        }
    }
    
    func deleteTranscription(bookID: UUID) async {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = bookID.uuidString
                    
                    // Delete sentences
                    try db.execute(
                        sql: "DELETE FROM sentences WHERE book_id = ?",
                        arguments: [bookIDString]
                    )
                    
                    // Delete chunks
                    try db.execute(
                        sql: "DELETE FROM chunks WHERE book_id = ?",
                        arguments: [bookIDString]
                    )
                    
                    print("✅ [TranscriptionDatabase] Deleted transcription data for book \(bookIDString)")
                }
                continuation.resume()
            } catch {
                print("❌ [TranscriptionDatabase] Failed to delete transcription: \(error)")
                continuation.resume()
            }
        }
    }
    
    func clearTranscription(bookID: UUID) async {
        await deleteTranscription(bookID: bookID)
    }
    
    // MARK: - Chapter Transcription Methods
    
    func isChapterTranscribed(bookID: UUID, chapterID: UUID) async -> Bool {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let isTranscribed = try dbQueue.read { db -> Bool in
                    let bookIDString = bookID.uuidString
                    let chapterIDString = chapterID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT is_complete
                            FROM chapter_transcriptions
                            WHERE book_id = ? AND chapter_id = ?
                        """,
                        arguments: [bookIDString, chapterIDString]
                    )
                    
                    if let isComplete = row?["is_complete"] as Int64? {
                        return isComplete == 1
                    }
                    return false
                }
                continuation.resume(returning: isTranscribed)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to check chapter transcription: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    func isChapterTranscribing(bookID: UUID, chapterID: UUID) async -> Bool {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let isTranscribing = try dbQueue.read { db -> Bool in
                    let bookIDString = bookID.uuidString
                    let chapterIDString = chapterID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT is_complete
                            FROM chapter_transcriptions
                            WHERE book_id = ? AND chapter_id = ?
                        """,
                        arguments: [bookIDString, chapterIDString]
                    )
                    
                    if let isComplete = row?["is_complete"] as Int64? {
                        return isComplete == 0 // 0 means in progress
                    }
                    return false
                }
                continuation.resume(returning: isTranscribing)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to check chapter transcribing status: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    func markChapterTranscribing(bookID: UUID, chapterID: UUID, startTime: TimeInterval, endTime: TimeInterval) async {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = bookID.uuidString
                    let chapterIDString = chapterID.uuidString
                    let idString = UUID().uuidString
                    let createdAt = Date().timeIntervalSince1970
                    
                    try db.execute(
                        sql: """
                            INSERT OR REPLACE INTO chapter_transcriptions 
                            (id, book_id, chapter_id, start_time, end_time, is_complete, created_at)
                            VALUES (?, ?, ?, ?, ?, 0, ?)
                        """,
                        arguments: [idString, bookIDString, chapterIDString, startTime, endTime, createdAt]
                    )
                    
                    print("💾 [TranscriptionDatabase] Marked chapter as transcribing: bookID=\(bookIDString), chapterID=\(chapterIDString)")
                }
                continuation.resume()
            } catch {
                print("❌ [TranscriptionDatabase] Failed to mark chapter as transcribing: \(error)")
                continuation.resume()
            }
        }
    }
    
    func markChapterComplete(bookID: UUID, chapterID: UUID) async {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = bookID.uuidString
                    let chapterIDString = chapterID.uuidString
                    
                    try db.execute(
                        sql: """
                            UPDATE chapter_transcriptions
                            SET is_complete = 1
                            WHERE book_id = ? AND chapter_id = ?
                        """,
                        arguments: [bookIDString, chapterIDString]
                    )
                    
                    print("✅ [TranscriptionDatabase] Marked chapter as complete: bookID=\(bookIDString), chapterID=\(chapterIDString)")
                }
                continuation.resume()
            } catch {
                print("❌ [TranscriptionDatabase] Failed to mark chapter as complete: \(error)")
                continuation.resume()
            }
        }
    }
    
    func getTranscribedChapters(bookID: UUID) async -> Set<UUID> {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let chapterIDs = try dbQueue.read { db -> Set<UUID> in
                    let bookIDString = bookID.uuidString
                    
                    let rows = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT chapter_id
                            FROM chapter_transcriptions
                            WHERE book_id = ? AND is_complete = 1
                        """,
                        arguments: [bookIDString]
                    )
                    
                    var chapterIDSet: Set<UUID> = []
                    for row in rows {
                        if let chapterIDString = row["chapter_id"] as String?,
                           let chapterID = UUID(uuidString: chapterIDString) {
                            chapterIDSet.insert(chapterID)
                        }
                    }
                    return chapterIDSet
                }
                continuation.resume(returning: chapterIDs)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get transcribed chapters: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    func loadSentencesForChapter(bookID: UUID, chapterID: UUID) async -> [TranscribedSentence] {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let sentences = try dbQueue.read { db -> [TranscribedSentence] in
                    let bookIDString = bookID.uuidString
                    let chapterIDString = chapterID.uuidString
                    
                    let rows = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT id, book_id, text, start_time, end_time, chapter_id, created_at
                            FROM sentences
                            WHERE book_id = ? AND chapter_id = ?
                            ORDER BY start_time ASC
                        """,
                        arguments: [bookIDString, chapterIDString]
                    )
                    
                    let sentences = rows.compactMap { row -> TranscribedSentence? in
                        guard let idString = row["id"] as String?,
                              let id = UUID(uuidString: idString),
                              let text = row["text"] as String?,
                              let startTime = row["start_time"] as Double?,
                              let endTime = row["end_time"] as Double? else {
                            return nil
                        }
                        return TranscribedSentence(
                            id: id,
                            text: text,
                            startTime: startTime,
                            endTime: endTime
                        )
                    }
                    
                    print("💾 [TranscriptionDatabase] Loaded \(sentences.count) sentences for chapter \(chapterIDString)")
                    return sentences
                }
                continuation.resume(returning: sentences)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to load sentences for chapter: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    func saveChapterTranscription(bookID: UUID, chapterID: UUID, sentences: [TranscribedSentence]) async throws {
        await ensureInitialized()
        
        guard let dbQueue = dbQueue else {
            throw DatabaseError.databaseNotInitialized
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = bookID.uuidString
                    let chapterIDString = chapterID.uuidString
                    let createdAt = Date().timeIntervalSince1970
                    
                    print("💾 [TranscriptionDatabase] Saving chapter transcription: bookID=\(bookIDString), chapterID=\(chapterIDString), \(sentences.count) sentences")
                    
                    // Delete existing sentences for this chapter
                    try db.execute(
                        sql: """
                            DELETE FROM sentences
                            WHERE book_id = ? AND chapter_id = ?
                        """,
                        arguments: [bookIDString, chapterIDString]
                    )
                    
                    // Insert sentences
                    for sentence in sentences {
                        let sentenceIDString = sentence.id.uuidString
                        
                        try db.execute(
                            sql: """
                                INSERT OR REPLACE INTO sentences 
                                (id, book_id, text, start_time, end_time, chapter_id, created_at)
                                VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                            arguments: [
                                sentenceIDString,
                                bookIDString,
                                sentence.text,
                                sentence.startTime,
                                sentence.endTime,
                                chapterIDString,
                                createdAt
                            ]
                        )
                    }
                    
                    // Mark chapter as complete
                    try db.execute(
                        sql: """
                            UPDATE chapter_transcriptions
                            SET is_complete = 1
                            WHERE book_id = ? AND chapter_id = ?
                        """,
                        arguments: [bookIDString, chapterIDString]
                    )
                    
                    print("✅ [TranscriptionDatabase] Saved chapter transcription successfully")
                }
                continuation.resume()
            } catch {
                print("❌ [TranscriptionDatabase] Failed to save chapter transcription: \(error)")
                continuation.resume(throwing: DatabaseError.insertFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - Database Errors

enum DatabaseError: LocalizedError {
    case databaseNotInitialized
    case insertFailed(String)
    case queryFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Database not initialized"
        case .insertFailed(let message):
            return "Failed to insert: \(message)"
        case .queryFailed(let message):
            return "Failed to query: \(message)"
        }
    }
}


