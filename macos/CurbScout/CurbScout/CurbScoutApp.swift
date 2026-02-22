import SwiftUI

@main
struct CurbScoutApp: App {
    @State private var pipelineStatus = PipelineStatus.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)

        MenuBarExtra("CurbScout", systemImage: pipelineStatus.icon) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pipeline: \(pipelineStatus.state.rawValue)")
                    .font(.headline)
                Divider()
                Text("Sightings: \(pipelineStatus.sightingCount)")
                Text("Last Sync: \(pipelineStatus.lastSync)")
                Divider()
                Button("Open Dashboard") {
                    NSWorkspace.shared.open(URL(string: "http://localhost:5173")!)
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
    }
}
