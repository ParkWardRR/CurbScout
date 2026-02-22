import Foundation

/// Lightweight data transfer objects matching SQLite row shapes.

struct SightingRow: Identifiable, Hashable {
    let id: String
    let rideId: String
    let bestCropId: String
    let timestamp: String
    let predictedMake: String
    let predictedModel: String
    let predictedYear: String?
    let confidence: Double
    let reviewStatus: String
    let sanityWarning: Bool
    let sanityWarningText: String?
    let lat: Double?
    let lng: Double?
    let attrsJson: String?

    var isIntelligence: Bool {
        predictedMake == "parking_sign" || predictedMake == "hazard"
    }

    var displayTitle: String {
        if predictedMake == "parking_sign" { return "🅿️ Parking Sign" }
        if predictedMake == "hazard" { return "⚠️ \(predictedModel.replacingOccurrences(of: "_", with: " ").capitalized)" }
        return "\(predictedMake) \(predictedModel)"
    }

    var cropURL: URL? {
        // Try local file first, then GCS proxy
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localPath = home.appendingPathComponent("CurbScout/derived/crops").appendingPathComponent("\(bestCropId)_crop.jpg")
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }
        return nil
    }
}

struct RideRow: Identifiable {
    let id: String
    let startTs: String
    let endTs: String?
    let videoCount: Int
    let sightingCount: Int

    var displayDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: startTs) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return startTs
    }
}
