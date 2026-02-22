import Foundation
import DiskArbitration

/// Watches for external camera mounts (GoPro, dashcam) via DiskArbitration.
/// When detected, triggers the pipeline auto-start.
class CameraWatcher {
    static let shared = CameraWatcher()

    private var session: DASession?
    private var isWatching = false

    func startWatching() {
        guard !isWatching else { return }
        isWatching = true

        session = DASessionCreate(kCFAllocatorDefault)
        guard let session = session else { return }

        DASessionSetDispatchQueue(session, DispatchQueue.global(qos: .background))

        let matchDict: CFDictionary = [
            kDADiskDescriptionMediaRemovableKey: true
        ] as CFDictionary

        DARegisterDiskAppearedCallback(session, matchDict, { disk, context in
            let description = DADiskCopyDescription(disk) as? [String: Any]
            let volumeName = description?[kDADiskDescriptionVolumeNameKey as String] as? String ?? "Unknown"

            print("📷 External media detected: \(volumeName)")

            // Check if it looks like a camera (GoPro, DCIM folder presence)
            if let mountPoint = description?[kDADiskDescriptionVolumePathKey as String] as? URL {
                let dcimPath = mountPoint.appendingPathComponent("DCIM")
                if FileManager.default.fileExists(atPath: dcimPath.path) {
                    print("🎬 Camera DCIM folder found at \(dcimPath.path). Triggering pipeline...")
                    CameraWatcher.triggerPipeline(source: dcimPath)
                }
            }
        }, nil)
    }

    private static func triggerPipeline(source: URL) {
        // Launch the pipeline script in the background
        let task = Process()
        let home = FileManager.default.homeDirectoryForCurrentUser
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [
            home.appendingPathComponent("antigravity/CurbScout/scripts/run-pipeline.sh").path,
            "--source", source.path
        ]
        task.environment = ProcessInfo.processInfo.environment

        do {
            try task.run()
            print("✅ Pipeline launched for \(source.lastPathComponent)")
        } catch {
            print("❌ Failed to launch pipeline: \(error)")
        }
    }

    func stopWatching() {
        session = nil
        isWatching = false
    }
}
