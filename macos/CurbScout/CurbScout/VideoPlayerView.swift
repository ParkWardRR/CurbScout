import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @State private var rides: [RideRow] = []
    @State private var selectedRide: RideRow?
    @State private var videoURL: URL?
    @State private var player = AVPlayer()

    var body: some View {
        HSplitView {
            // Ride list
            List(rides, selection: $selectedRide) { ride in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ride.displayDate)
                        .font(.headline)
                    HStack {
                        Label("\(ride.videoCount)", systemImage: "video.fill")
                        Label("\(ride.sightingCount)", systemImage: "car.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(ride)
                .onTapGesture {
                    selectedRide = ride
                    loadVideo(for: ride)
                }
            }
            .frame(minWidth: 220, maxWidth: 300)

            // Video player
            VStack {
                if videoURL != nil {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 16) {
                        Button(action: { seekRelative(-5) }) {
                            Image(systemName: "gobackward.5")
                        }
                        Button(action: { togglePlayPause() }) {
                            Image(systemName: "playpause.fill")
                        }
                        Button(action: { seekRelative(5) }) {
                            Image(systemName: "goforward.5")
                        }
                        Button(action: { seekRelative(-1.0/30.0) }) {
                            Image(systemName: "chevron.left")
                        }
                        .help("Previous frame")
                        Button(action: { seekRelative(1.0/30.0) }) {
                            Image(systemName: "chevron.right")
                        }
                        .help("Next frame")
                    }
                    .font(.title2)
                    .padding()
                } else {
                    ContentUnavailableView(
                        "Select a Ride",
                        systemImage: "play.rectangle",
                        description: Text("Choose a ride from the left to scrub through its video.")
                    )
                }
            }
            .padding()
        }
        .onAppear { rides = DatabaseBridge.shared.fetchRides() }
    }

    private func loadVideo(for ride: RideRow) {
        // Try to find the first video file for this ride
        let home = FileManager.default.homeDirectoryForCurrentUser
        let videosDir = home.appendingPathComponent("CurbScout/raw_video")

        if let files = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil),
           let first = files.first(where: { $0.pathExtension == "mp4" || $0.pathExtension == "mov" }) {
            videoURL = first
            player.replaceCurrentItem(with: AVPlayerItem(url: first))
        }
    }

    private func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func seekRelative(_ seconds: Double) {
        guard let currentTime = player.currentItem?.currentTime() else { return }
        let target = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

#Preview {
    VideoPlayerView()
}
