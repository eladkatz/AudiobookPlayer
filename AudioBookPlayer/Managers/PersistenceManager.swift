import Foundation

class PersistenceManager {
    static let shared = PersistenceManager()
    
    private let booksKey = "saved_books"
    private let settingsKey = "playback_settings"
    private let currentBookKey = "current_book_id"
    private let currentPositionKey = "current_position"
    
    private init() {}
    
    // MARK: - Books Persistence
    func saveBooks(_ books: [Book]) {
        if let encoded = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(encoded, forKey: booksKey)
        }
    }
    
    func loadBooks() -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: booksKey),
              let books = try? JSONDecoder().decode([Book].self, from: data) else {
            return []
        }
        return books
    }
    
    // MARK: - Settings Persistence
    func saveSettings(_ settings: PlaybackSettings) {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    func loadSettings() -> PlaybackSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(PlaybackSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    // MARK: - Current Book Persistence
    func saveCurrentBookID(_ bookID: UUID?) {
        if let bookID = bookID {
            UserDefaults.standard.set(bookID.uuidString, forKey: currentBookKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentBookKey)
        }
    }
    
    func loadCurrentBookID() -> UUID? {
        guard let uuidString = UserDefaults.standard.string(forKey: currentBookKey) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }
    
    // MARK: - Position Persistence
    func savePosition(for bookID: UUID, position: TimeInterval) {
        let key = "\(currentPositionKey)_\(bookID.uuidString)"
        UserDefaults.standard.set(position, forKey: key)
    }
    
    func loadPosition(for bookID: UUID) -> TimeInterval {
        let key = "\(currentPositionKey)_\(bookID.uuidString)"
        return UserDefaults.standard.double(forKey: key)
    }
}

