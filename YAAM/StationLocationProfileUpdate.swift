import Foundation

extension StationLocationSelection {
    /// Return an edited draft; persistence stays behind the station editor's existing Save action.
    func applying(to profile: StationProfile) -> StationProfile {
        var updated = profile
        updated.grid = grid
        updated.latitude = latitude
        updated.longitude = longitude
        return updated
    }
}
