//
//  FieldParkMapView.swift
//  YAAM
//
//  Offline Park & Summit Directory Explorer with Native MapKit Visualization.
//  Enables instant offline search by reference, name, or GPS/Grid proximity,
//  and one-tap activation session setup.
//

import CoreLocation
import MapKit
import SwiftUI

public struct FieldParkMapView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var directory = POTAParkDirectory.shared
    @ObservedObject private var potaEngine = POTASOTAEngine.shared

    @State private var searchQuery: String = ""
    @State private var selectedPark: ParkDirectoryEntry?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6892, longitude: 51.3890), // Default center
        span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
    )

    public init() {}

    private var currentStationCoord: CLLocationCoordinate2D {
        if let rover = RoverModeEngine.shared.activeSession, let box = MaidenheadGridEngine.boundingBox(for: rover.targetGrid) {
            return CLLocationCoordinate2D(latitude: box.center.latitude, longitude: box.center.longitude)
        }
        let home = appState.effectiveStationCoordinate
        return CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
    }

    public var body: some View {
        HSplitView {
            // Left Pane: Search & Park Directory List
            VStack(spacing: 0) {
                searchHeader

                Divider()

                parkListView
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)

            // Right Pane: Native MapKit Map & Park Details Card
            ZStack(alignment: .bottomTrailing) {
                mapView

                if let park = selectedPark {
                    parkDetailsOverlayCard(park: park)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            setupInitialRegion()
        }
    }

    // MARK: - Search Header
    private var searchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search park ref (e.g. EP-0005, K-0001), name...", text: $searchQuery)
                    .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            HStack {
                Text("\(directory.search(query: searchQuery).count) Parks/Summits Cached")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Nearby Parks") {
                    searchQuery = ""
                    if let first = directory.nearestParks(to: currentStationCoord).first {
                        selectPark(first.entry)
                    }
                }
                .font(.caption2.bold())
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Park List View
    private var parkListView: some View {
        let results = directory.search(query: searchQuery)

        return List(selection: $selectedPark) {
            ForEach(results) { park in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: park.program.icon)
                            .foregroundStyle(park.program == .pota ? .green : .orange)
                            .font(.system(size: 11))

                        Text(park.reference)
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(park.gridSquare)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(park.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack {
                        Text("\(park.country) · \(park.stateOrRegion)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        let dist = park.distance(from: currentStationCoord)
                        Text(String(format: "%.0f km", dist))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .tag(park)
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedPark) { _, newPark in
            if let p = newPark {
                zoomToPark(p)
            }
        }
    }

    // MARK: - Map View
    private var mapView: some View {
        Map(coordinateRegion: $mapRegion, annotationItems: directory.entries) { park in
            MapAnnotation(coordinate: park.coordinate) {
                Button {
                    selectPark(park)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: park.program.icon)
                            .font(.system(size: selectedPark?.id == park.id ? 18 : 12))
                            .foregroundStyle(selectedPark?.id == park.id ? .white : (park.program == .pota ? .green : .orange))
                            .padding(selectedPark?.id == park.id ? 6 : 4)
                            .background(
                                selectedPark?.id == park.id ? Color.accentColor : Color.black.opacity(0.7),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .shadow(radius: 3)

                        if selectedPark?.id == park.id {
                            Text(park.reference)
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Park Details Overlay Card
    private func parkDetailsOverlayCard(park: ParkDirectoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: park.program.icon)
                    .foregroundStyle(park.program == .pota ? .green : .orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(park.reference)
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                    Text(park.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    selectedPark = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Country / State:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(park.country) / \(park.stateOrRegion)")
                        .font(.caption.bold())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Grid Square:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(park.gridSquare)
                        .font(.caption.monospaced().bold())
                }

                if let elev = park.elevationMeters {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Elevation:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(elev) m")
                            .font(.caption.bold())
                    }
                }
            }

            HStack {
                Spacer()

                Button {
                    let call = appState.activeStationProfile?.normalizedCallsign ?? appState.currentStationCallsign
                    potaEngine.startSession(
                        program: park.program,
                        reference: park.reference,
                        parkName: park.name,
                        callsign: call,
                        grid: park.gridSquare,
                        latitude: park.latitude,
                        longitude: park.longitude
                    )
                } label: {
                    Label("Activate This Park", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(radius: 8)
    }

    // MARK: - Navigation / Zoom
    private func setupInitialRegion() {
        let center = currentStationCoord
        mapRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
        )
    }

    private func selectPark(_ park: ParkDirectoryEntry) {
        selectedPark = park
        zoomToPark(park)
    }

    private func zoomToPark(_ park: ParkDirectoryEntry) {
        guard park.latitude != 0.0 || park.longitude != 0.0 else { return }
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: park.latitude, longitude: park.longitude),
                span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
            )
        }
    }
}
