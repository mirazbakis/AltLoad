import MapKit
import SwiftUI

/// Tools › Location: pick a spot on the map and this iPhone reports it as its
/// location until you stop. Uses the developer location simulation, so every app sees it.
struct LocationView: View {
    @ObservedObject private var spoofer = LocationSpoofer.shared
    @ObservedObject private var pairings = PairingStore.shared

    @State private var position: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var query = ""
    @State private var results: [MKMapItem] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $position) {
                    if let pin {
                        Marker("Simulated", systemImage: "location.fill", coordinate: pin)
                            .tint(Aurora.accent)
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) { pin = coordinate }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            controls
                .padding(16)
        }
        .navigationTitle("Location")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search for a place")
        .searchSuggestions {
            ForEach(results, id: \.self) { item in
                Button {
                    choose(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Place")
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(Aurora.secondaryText)
                        }
                    }
                }
            }
        }
        .onSubmit(of: .search) { Task { await runSearch() } }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            await runSearch()
        }
        .onAppear {
            if case .active(let coordinate) = spoofer.state {
                pin = coordinate
                position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
        }
    }

    private var controls: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                statusLine
                if let pin {
                    InfoRow(title: "Pin", value: String(format: "%.5f, %.5f", pin.latitude, pin.longitude), monospaced: true)
                } else {
                    Text("Tap the map or search to drop a pin.")
                        .font(.footnote)
                        .foregroundStyle(Aurora.secondaryText)
                }
                HStack(spacing: 10) {
                    Button {
                        if let pin { spoofer.simulate(pin) }
                    } label: {
                        Label(spoofer.isRunning ? "Move Here" : "Simulate", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AltLoadButtonStyle())
                    .disabled(pin == nil || pairings.selfPairing == nil)

                    if spoofer.isRunning {
                        Button {
                            spoofer.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AltLoadButtonStyle(prominent: false))
                    }
                }
            }
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch spoofer.state {
        case .idle:
            Label(pairings.selfPairing == nil ? "Pair this iPhone first" : "Using the real location",
                  systemImage: "location")
                .font(.subheadline.weight(.semibold))
        case .starting(let stage):
            HStack(spacing: 10) {
                ProgressView()
                Text(stage).font(.subheadline)
            }
        case .active:
            Label("Simulating. Every app sees the pin.", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Aurora.success)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Aurora.danger)
        }
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        results = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }

    private func choose(_ item: MKMapItem) {
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        pin = coordinate
        position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000))
        query = ""
        results = []
    }
}

private extension MKMapItem {
    /// A short address under the place's name.
    var subtitle: String? {
        if #available(iOS 26, *) {
            return address?.shortAddress
        }
        return placemark.title
    }
}
