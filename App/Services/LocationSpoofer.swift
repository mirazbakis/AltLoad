import AltLoadFFI
import CoreLocation
import Foundation

/// Simulates this iPhone's location through DVT until stopped. The device only
/// keeps a simulated location while the connection is open, so the session holds
/// a tunnel on its own queue; the background keep-alive helps it survive.
@MainActor
final class LocationSpoofer: ObservableObject {
    static let shared = LocationSpoofer()

    enum State: Equatable {
        case idle
        case starting(String)
        case active(CLLocationCoordinate2D)
        case failed(String)

        static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.idle, .idle): true
            case let (.starting(x), .starting(y)): x == y
            case let (.active(x), .active(y)): x.latitude == y.latitude && x.longitude == y.longitude
            case let (.failed(x), .failed(y)): x == y
            default: false
            }
        }
    }

    @Published private(set) var state: State = .idle
    /// Stop pressed before the session was up; it's stopped again once it is.
    private var stopRequested = false

    var isRunning: Bool {
        switch state {
        case .starting, .active: true
        default: false
        }
    }

    private init() {}

    /// Starts simulating `coordinate`, or moves a running session there.
    func simulate(_ coordinate: CLLocationCoordinate2D) {
        if isRunning {
            altload_location_update(coordinate.latitude, coordinate.longitude)
            state = .active(coordinate)
            return
        }
        stopRequested = false
        state = .starting("Opening device link…")
        Task {
            do {
                let dir = try await DeveloperDiskImage.ensureDownloaded { stage, _ in
                    self.state = .starting(stage)
                }
                // Returns only once stopped.
                try await DeviceOps.run(
                    ["op": "simulate_location", "lat": coordinate.latitude, "lon": coordinate.longitude, "ddiDir": dir.path],
                    on: DeviceOps.longRunningQueue
                ) { stage, _ in
                    guard self.isRunning else { return }
                    if stage == "Simulating location" {
                        if self.stopRequested { altload_location_stop(); return }
                        if case .starting = self.state { self.state = .active(coordinate) }
                    } else {
                        self.state = .starting(stage)
                    }
                }
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Ends the session; iOS goes back to the real location.
    func stop() {
        stopRequested = true
        altload_location_stop()
        if case .failed = state { state = .idle }
    }
}
