import Foundation
import Observation

@Observable
class PipelineStatus {
    static let shared = PipelineStatus()

    enum State: String {
        case idle = "Idle"
        case processing = "Processing"
        case syncing = "Syncing"
        case error = "Error"
    }

    var state: State = .idle
    var sightingCount: Int = 0
    var lastSync: String = "Never"

    var icon: String {
        switch state {
        case .idle: return "circle.fill"
        case .processing: return "gear.badge"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var timer: Timer?

    init() {
        startPolling()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        refreshStatus()
    }

    private func refreshStatus() {
        // Read status from a file the Python pipeline writes
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statusFile = home.appendingPathComponent("CurbScout/data/pipeline_status.json")

        guard let data = try? Data(contentsOf: statusFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let stateStr = json["state"] as? String {
            state = State(rawValue: stateStr) ?? .idle
        }
        if let count = json["sighting_count"] as? Int {
            sightingCount = count
        }
        if let sync = json["last_sync"] as? String {
            lastSync = sync
        }
    }
}
