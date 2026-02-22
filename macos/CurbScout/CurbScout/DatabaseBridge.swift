import Foundation
import SQLite3

/// Lightweight read-only bridge to the pipeline's SQLite database.
/// SwiftData is used for the UI models, but we read raw rows from the existing DB.
class DatabaseBridge {
    static let shared = DatabaseBridge()

    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/CurbScout/data/curbscout.db"
        openDatabase()
    }

    private func openDatabase() {
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("⚠️ Cannot open database at \(dbPath)")
            db = nil
        }
    }

    func fetchSightings(limit: Int = 200) -> [SightingRow] {
        guard let db = db else { return [] }
        var rows: [SightingRow] = []
        var stmt: OpaquePointer?

        let query = """
        SELECT s.id, s.ride_id, s.best_crop_id, s.timestamp,
               s.predicted_make, s.predicted_model, s.predicted_year,
               s.classification_confidence, s.review_status,
               s.sanity_warning, s.sanity_warning_text,
               s.lat, s.lng, s.attrs_json
        FROM SIGHTING s
        WHERE s.deleted = 0
        ORDER BY s.created_at DESC
        LIMIT ?
        """

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let row = SightingRow(
                    id: String(cString: sqlite3_column_text(stmt, 0)),
                    rideId: String(cString: sqlite3_column_text(stmt, 1)),
                    bestCropId: String(cString: sqlite3_column_text(stmt, 2)),
                    timestamp: String(cString: sqlite3_column_text(stmt, 3)),
                    predictedMake: String(cString: sqlite3_column_text(stmt, 4)),
                    predictedModel: String(cString: sqlite3_column_text(stmt, 5)),
                    predictedYear: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
                    confidence: sqlite3_column_double(stmt, 7),
                    reviewStatus: String(cString: sqlite3_column_text(stmt, 8)),
                    sanityWarning: sqlite3_column_int(stmt, 9) == 1,
                    sanityWarningText: sqlite3_column_text(stmt, 10).map { String(cString: $0) },
                    lat: sqlite3_column_type(stmt, 11) != SQLITE_NULL ? sqlite3_column_double(stmt, 11) : nil,
                    lng: sqlite3_column_type(stmt, 12) != SQLITE_NULL ? sqlite3_column_double(stmt, 12) : nil,
                    attrsJson: sqlite3_column_text(stmt, 13).map { String(cString: $0) }
                )
                rows.append(row)
            }
        }
        sqlite3_finalize(stmt)
        return rows
    }

    func fetchRides(limit: Int = 50) -> [RideRow] {
        guard let db = db else { return [] }
        var rows: [RideRow] = []
        var stmt: OpaquePointer?

        let query = "SELECT id, start_ts, end_ts, video_count, sighting_count FROM RIDE ORDER BY start_ts DESC LIMIT ?"

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let row = RideRow(
                    id: String(cString: sqlite3_column_text(stmt, 0)),
                    startTs: String(cString: sqlite3_column_text(stmt, 1)),
                    endTs: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                    videoCount: Int(sqlite3_column_int(stmt, 3)),
                    sightingCount: Int(sqlite3_column_int(stmt, 4))
                )
                rows.append(row)
            }
        }
        sqlite3_finalize(stmt)
        return rows
    }

    func updateReviewStatus(sightingId: String, status: String) {
        // For writes we open a separate read-write connection
        var writeDb: OpaquePointer?
        if sqlite3_open(dbPath, &writeDb) != SQLITE_OK { return }
        defer { sqlite3_close(writeDb) }

        var stmt: OpaquePointer?
        let query = "UPDATE SIGHTING SET review_status = ?, updated_at = ? WHERE id = ?"
        if sqlite3_prepare_v2(writeDb, query, -1, &stmt, nil) == SQLITE_OK {
            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(stmt, 1, (status as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (now as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (sightingId as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    deinit {
        sqlite3_close(db)
    }
}
