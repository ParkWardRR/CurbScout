import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: SightingGridView()) {
                    Label("Sightings", systemImage: "car.fill")
                }
                NavigationLink(destination: VideoPlayerView()) {
                    Label("Video Scrubber", systemImage: "play.rectangle.fill")
                }
                NavigationLink(destination: FleetStatusView()) {
                    Label("Fleet Status", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .navigationTitle("CurbScout")
        } detail: {
            SightingGridView()
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
