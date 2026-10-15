import AVFAudio
import CoreLocation
import Foundation

/// Keeps AltLoad running for the short while the user is in Settings tapping
/// "Pair with AltLoad". Two independent mechanisms:
///   - silent audio: a near-inaudible tone on a playback session, which iOS
///     treats as active output and keeps scheduled;
///   - location: background location updates.
/// Either one on its own is enough.
@MainActor
final class KeepAlive: NSObject {

    // MARK: - Silent audio

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioRunning = false

    func startAudio() {
        guard !audioRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps us alive in the background; .mixWithOthers so we
            // don't stop the user's music.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])

            // Build the format AFTER the session is active, and from the mixer's
            // own output, so the sample rate is real (the old code read the
            // output node before activation and got a 0 Hz format, so the buffer
            // never allocated and nothing played).
            engine.attach(player)
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { audioRunning = false; return }
            engine.connect(player, to: engine.mainMixerNode, format: format)

            let frames = AVAudioFrameCount(format.sampleRate) // one second, looped
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                audioRunning = false
                return
            }
            buffer.frameLength = frames

            // A very quiet 20 Hz tone. Genuinely non-silent output is what keeps
            // the session scheduled; the amplitude is low enough to be inaudible.
            if let channels = buffer.floatChannelData {
                let amplitude: Float = 0.003
                let step = 2 * Float.pi * 20 / Float(format.sampleRate)
                for frame in 0..<Int(frames) {
                    let value = sin(Float(frame) * step) * amplitude
                    for channel in 0..<Int(format.channelCount) {
                        channels[channel][frame] = value
                    }
                }
            }

            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            audioRunning = true
        } catch {
            audioRunning = false
        }
    }

    func stopAudio() {
        guard audioRunning else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        audioRunning = false
    }

    // MARK: - Location

    private lazy var location: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        m.distanceFilter = kCLDistanceFilterNone
        m.pausesLocationUpdatesAutomatically = false
        return m
    }()
    private var locationRunning = false

    var locationAuthorization: CLAuthorizationStatus { location.authorizationStatus }

    func startLocation() {
        guard !locationRunning else { return }
        locationRunning = true
        requestLocationAuthorization()
        beginLocationUpdatesIfAuthorized()
    }

    /// Asks for location access. iOS shows "Allow Once / Allow While Using /
    /// Don't Allow" the first time; picking "While Using" is enough. Calling it
    /// again once we already have When-In-Use is what surfaces "Change to Always
    /// Allow", which makes the keep-alive most reliable.
    func requestLocationAuthorization() {
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            location.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func beginLocationUpdatesIfAuthorized() {
        let status = location.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        if status == .authorizedAlways {
            location.allowsBackgroundLocationUpdates = true
        }
        location.startUpdatingLocation()
    }

    func stopLocation() {
        guard locationRunning else { return }
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        locationRunning = false
    }

    func stopAll() {
        stopAudio()
        stopLocation()
    }
}

extension KeepAlive: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            PairingController.shared.locationAuthorizationChanged(manager.authorizationStatus)
            guard locationRunning else { return }
            beginLocationUpdatesIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
