import Foundation
import CoreLocation
import Combine

@MainActor final class StationLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var fix: StationLocationFix?
    var point: GridLocationPoint? { fix?.point }
    var accuracy: Double? { fix?.accuracy }
    @Published private(set) var isLocating = false
    @Published private(set) var message = ""
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        stop()
        fix = nil
        isLocating = true
        message = "Finding your location…"
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.isLocating else { return }
            self.stop()
            self.message = self.point == nil ? "No fresh location was received. Try again, enter coordinates, or choose on the map." : "Best available location received. Review its reported accuracy."
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted: unavailable()
        @unknown default: unavailable()
        }
    }

    func stop() {
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation()
        isLocating = false
    }

    func cancel() {
        stop()
        message = ""
    }

    private func unavailable() {
        stop()
        message = "Location access is unavailable. Enable YAAM in System Settings → Privacy & Security → Location Services, or use manual entry or the map."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted: unavailable()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocating else { return }
        for location in locations {
            let candidate = GridLocationPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            guard StationLocationFixPolicy.accepts(point: candidate, accuracy: location.horizontalAccuracy,
                timestamp: location.timestamp, now: Date()), location.horizontalAccuracy < (accuracy ?? .infinity) else { continue }
            fix = StationLocationFix(point: candidate!, accuracy: location.horizontalAccuracy)
            message = "Location received. Reported accuracy: ±\(String(format: "%.0f", ceil(location.horizontalAccuracy))) m."
        }
        if let accuracy, accuracy <= 15 { stop() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isLocating else { return }
        if (error as? CLError)?.code == .locationUnknown { return }
        stop()
        message = "Location could not be received. Try again, enter coordinates, or choose on the map."
    }
}
