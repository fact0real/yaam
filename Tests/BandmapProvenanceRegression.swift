import Foundation
@main struct BandmapProvenanceRegression {
    static func main() {
        for source in ["Demo", "Manual Sim", "SIMULATED", "Synthetic RF", "WSJT-X (Simulator)", "Network Emulator"] {
            precondition(BandmapSourceProvenance.isSimulated(source), source)
        }
        for source in ["DX Cluster", "WSJT-X (station)", "TCI", "Simon DX", ""] {
            precondition(!BandmapSourceProvenance.isSimulated(source), source)
        }
        print("PASS Bandmap source provenance: manual simulation, demo and live sources")
    }
}
