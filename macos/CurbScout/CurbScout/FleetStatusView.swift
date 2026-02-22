import SwiftUI

struct FleetStatusView: View {
    @State private var hubStatus: String = "Checking..."
    @State private var workers: [[String: Any]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Fleet Status")
                .font(.title2.bold())

            GroupBox("GCP Hub Connection") {
                HStack {
                    Circle()
                        .fill(hubStatus == "Connected" ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(hubStatus)
                        .font(.body)
                    Spacer()
                    Button("Refresh") { checkHub() }
                }
                .padding(8)
            }

            GroupBox("Registered Workers") {
                if workers.isEmpty {
                    Text("No workers found or Hub unreachable.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(0..<workers.count, id: \.self) { i in
                        let w = workers[i]
                        HStack {
                            Circle()
                                .fill((w["status"] as? String) == "online" ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(w["hostname"] as? String ?? "Unknown")
                                .font(.body.bold())
                            Spacer()
                            Text("\(w["sighting_count"] as? Int ?? 0) sightings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        if i < workers.count - 1 { Divider() }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onAppear { checkHub() }
    }

    private func checkHub() {
        let hubURL = ProcessInfo.processInfo.environment["GCP_HUB_URL"] ?? "http://localhost:5173"
        guard let url = URL(string: "\(hubURL)/api/workers") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let workerList = json["workers"] as? [[String: Any]] {
                    self.workers = workerList
                    self.hubStatus = "Connected"
                } else {
                    self.hubStatus = error?.localizedDescription ?? "Disconnected"
                }
            }
        }.resume()
    }
}

#Preview {
    FleetStatusView()
}
