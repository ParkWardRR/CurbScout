import SwiftUI

struct SightingGridView: View {
    @State private var sightings: [SightingRow] = []
    @State private var selectedSighting: SightingRow?
    @State private var filterStatus: String = "all"

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)]

    var filteredSightings: [SightingRow] {
        switch filterStatus {
        case "pending": return sightings.filter { $0.reviewStatus == "pending" }
        case "reviewed": return sightings.filter { $0.reviewStatus != "pending" }
        case "intelligence": return sightings.filter { $0.isIntelligence }
        default: return sightings
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 12) {
                Text("Sightings")
                    .font(.title2.bold())
                Spacer()

                Picker("Filter", selection: $filterStatus) {
                    Text("All (\(sightings.count))").tag("all")
                    Text("Pending").tag("pending")
                    Text("Reviewed").tag("reviewed")
                    Text("Intelligence").tag("intelligence")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
            }
            .padding()

            Divider()

            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredSightings) { sighting in
                        SightingCardView(sighting: sighting, isSelected: selectedSighting?.id == sighting.id)
                            .onTapGesture {
                                selectedSighting = sighting
                            }
                    }
                }
                .padding()
            }
        }
        .sheet(item: $selectedSighting) { sighting in
            SightingDetailView(sighting: sighting) { action in
                performReview(sightingId: sighting.id, action: action)
                selectedSighting = nil
            }
        }
        .onAppear { loadSightings() }
    }

    private func loadSightings() {
        sightings = DatabaseBridge.shared.fetchSightings(limit: 500)
    }

    private func performReview(sightingId: String, action: String) {
        DatabaseBridge.shared.updateReviewStatus(sightingId: sightingId, status: action)
        loadSightings()
    }
}

// MARK: - Card

struct SightingCardView: View {
    let sighting: SightingRow
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                if let url = sighting.cropURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.gray.opacity(0.2))
                    }
                    .frame(height: 140)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.15))
                        .frame(height: 140)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                }

                if sighting.sanityWarning {
                    Text("⚠️")
                        .padding(4)
                        .background(.orange.opacity(0.8))
                        .clipShape(Circle())
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(sighting.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(sighting.predictedYear ?? "Unknown Year")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(Int(sighting.confidence * 100))%")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(confidenceColor.opacity(0.2))
                        .foregroundColor(confidenceColor)
                        .clipShape(Capsule())

                    Spacer()

                    if sighting.reviewStatus != "pending" {
                        Text(sighting.reviewStatus.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.blue, lineWidth: 2)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var confidenceColor: Color {
        if sighting.confidence >= 0.8 { return .green }
        if sighting.confidence >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Detail Sheet

struct SightingDetailView: View {
    let sighting: SightingRow
    let onAction: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            if let url = sighting.cropURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 8) {
                Text(sighting.displayTitle)
                    .font(.title2.bold())
                Text(sighting.predictedYear ?? "")
                    .foregroundStyle(.secondary)
                Text("\(Int(sighting.confidence * 100))% confidence")
                    .font(.callout)
            }

            Divider()

            HStack(spacing: 16) {
                Button(action: { onAction("confirmed") }) {
                    Label("Confirm", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: { onAction("deleted") }) {
                    Label("Delete", systemImage: "trash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button("Close") { onAction(sighting.reviewStatus) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}

#Preview {
    SightingGridView()
}
