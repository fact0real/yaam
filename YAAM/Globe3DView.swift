//
//  Globe3DView.swift
//  YAAM
//
//  Hardware-Accelerated 3D Metal / SceneKit Globe (Zero-Flicker & Low-CPU Optimized)
//  Displays interactive 3D Earth, Astronomical Solar Day/Night Illumination,
//  Precise Country Boundaries, Country Names & Flags, and 3D Geodesic Arcs.
//

import AppKit
import SceneKit
import SwiftUI

// MARK: - 3D Map Marker Data Model

public struct Globe3DMarker: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let callsign: String
    public let flag: String
    public let coordinate: GeoCoordinate
    public let grid: String
    public let band: String
    public let mode: String
    public let snr: Int?
    public let isHome: Bool
    public let timestamp: Date

    public init(
        callsign: String,
        flag: String,
        coordinate: GeoCoordinate,
        grid: String = "",
        band: String = "20M",
        mode: String = "FT8",
        snr: Int? = nil,
        isHome: Bool = false,
        timestamp: Date = Date()
    ) {
        self.callsign = callsign
        self.flag = flag
        self.coordinate = coordinate
        self.grid = grid
        self.band = band
        self.mode = mode
        self.snr = snr
        self.isHome = isHome
        self.timestamp = timestamp
    }
}

// MARK: - SceneKit 3D Globe NSViewRepresentable

public struct Globe3DSceneView: NSViewRepresentable {
    public var homeCoordinate: GeoCoordinate
    public var markers: [Globe3DMarker]
    public var showGreatCircleArcs: Bool
    public var showDayNightShadow: Bool
    public var showCountryLabels: Bool
    public var onSelectMarker: ((Globe3DMarker) -> Void)?

    public init(
        homeCoordinate: GeoCoordinate,
        markers: [Globe3DMarker],
        showGreatCircleArcs: Bool = true,
        showDayNightShadow: Bool = true,
        showCountryLabels: Bool = true,
        onSelectMarker: ((Globe3DMarker) -> Void)? = nil
    ) {
        self.homeCoordinate = homeCoordinate
        self.markers = markers
        self.showGreatCircleArcs = showGreatCircleArcs
        self.showDayNightShadow = showDayNightShadow
        self.showCountryLabels = showCountryLabels
        self.onSelectMarker = onSelectMarker
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0)
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 30
        scnView.rendersContinuously = false
        scnView.isPlaying = true

        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        context.coordinator.scnView = scnView

        context.coordinator.setupScene(home: homeCoordinate, showLabels: showCountryLabels)
        context.coordinator.updateMarkersAndArcs(markers: markers, home: homeCoordinate, showArcs: showGreatCircleArcs)
        context.coordinator.updateSunPosition(showDayNight: showDayNightShadow)
        return scnView
    }

    public func updateNSView(_ scnView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateTextureIfNeeded(showLabels: showCountryLabels)
        context.coordinator.updateMarkersAndArcs(markers: markers, home: homeCoordinate, showArcs: showGreatCircleArcs)
        context.coordinator.updateSunPosition(showDayNight: showDayNightShadow)
    }

    // MARK: - Coordinator & Scene Architecture

    public class Coordinator: NSObject {
        var parent: Globe3DSceneView
        let scene = SCNScene()
        weak var scnView: SCNView?

        private let earthRadius: CGFloat = 6.0
        private var earthNode: SCNNode?
        private var earthMaterial: SCNMaterial?
        private var currentTextureHasLabels: Bool = true
        private var sunLightNode: SCNNode?
        private var ambientLightNode: SCNNode?
        private var markersContainer = SCNNode()
        private var arcsContainer = SCNNode()
        private var markerLookup: [String: Globe3DMarker] = [:]
        private var lastRenderedSignature: String = ""

        private static var textureCache: [Bool: NSImage] = [:]

        init(_ parent: Globe3DSceneView) {
            self.parent = parent
            super.init()
        }

        func setupScene(home: GeoCoordinate, showLabels: Bool) {
            scene.rootNode.enumerateChildNodes { node, _ in node.removeFromParentNode() }

            // 1. Camera - Positioned to face user's Home Station (Tehran / Home QTH)
            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.zNear = 0.5
            camera.zFar = 100.0
            camera.fieldOfView = 42

            let homeCamPos = cartesianCoordinate(lat: home.latitude, lon: home.longitude, radius: 17.5)
            cameraNode.camera = camera
            cameraNode.position = homeCamPos
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)

            // 2. Ambient Light
            let ambientLight = SCNLight()
            ambientLight.type = .ambient
            ambientLight.color = NSColor(white: 0.58, alpha: 1.0)
            let ambNode = SCNNode()
            ambNode.light = ambientLight
            scene.rootNode.addChildNode(ambNode)
            self.ambientLightNode = ambNode

            // 3. Sun Directional Light
            let sunLight = SCNLight()
            sunLight.type = .directional
            sunLight.color = NSColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
            sunLight.castsShadow = true
            let sNode = SCNNode()
            sNode.light = sunLight
            scene.rootNode.addChildNode(sNode)
            self.sunLightNode = sNode

            // 4. Earth Sphere with High-Resolution Country Borders & Labels
            let sphere = SCNSphere(radius: earthRadius)
            sphere.segmentCount = 96
            let earthMat = SCNMaterial()
            earthMat.diffuse.contents = Coordinator.cachedEarthTexture(showLabels: showLabels)
            earthMat.specular.contents = NSColor(white: 0.35, alpha: 1.0)
            earthMat.shininess = 28.0
            sphere.materials = [earthMat]
            self.earthMaterial = earthMat
            self.currentTextureHasLabels = showLabels

            let eNode = SCNNode(geometry: sphere)
            scene.rootNode.addChildNode(eNode)
            self.earthNode = eNode

            // 5. Atmosphere Glow Shell
            let atmosSphere = SCNSphere(radius: earthRadius + 0.12)
            atmosSphere.segmentCount = 64
            let atmosMat = SCNMaterial()
            atmosMat.diffuse.contents = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.12)
            atmosMat.isDoubleSided = true
            atmosSphere.materials = [atmosMat]
            let atmosNode = SCNNode(geometry: atmosSphere)
            scene.rootNode.addChildNode(atmosNode)

            // Containers for dynamic pins and arcs
            scene.rootNode.addChildNode(markersContainer)
            scene.rootNode.addChildNode(arcsContainer)
        }

        func updateTextureIfNeeded(showLabels: Bool) {
            guard showLabels != currentTextureHasLabels, let earthMaterial else { return }
            earthMaterial.diffuse.contents = Coordinator.cachedEarthTexture(showLabels: showLabels)
            currentTextureHasLabels = showLabels
        }

        func updateSunPosition(showDayNight: Bool) {
            guard let sunLightNode, let ambientLightNode else { return }

            if !showDayNight {
                sunLightNode.position = SCNVector3(0, 10, 20)
                sunLightNode.look(at: SCNVector3(0, 0, 0))
                ambientLightNode.light?.color = NSColor(white: 0.80, alpha: 1.0)
                return
            }

            ambientLightNode.light?.color = NSColor(white: 0.50, alpha: 1.0)

            let subSolar = SolarEphemeris.calculate(at: Date())
            let sunPos = cartesianCoordinate(lat: subSolar.latitude, lon: subSolar.longitude, radius: 40.0)
            sunLightNode.position = sunPos
            sunLightNode.look(at: SCNVector3(0, 0, 0))
        }

        func updateMarkersAndArcs(markers: [Globe3DMarker], home: GeoCoordinate, showArcs: Bool) {
            // Signature diff check: Avoid re-creating 3D nodes if data hasn't changed
            let signature = computeSignature(markers: markers, home: home, showArcs: showArcs)
            guard signature != lastRenderedSignature else { return }
            lastRenderedSignature = signature

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0

            markersContainer.enumerateChildNodes { node, _ in node.removeFromParentNode() }
            arcsContainer.enumerateChildNodes { node, _ in node.removeFromParentNode() }
            markerLookup.removeAll()

            // 1. Plot Home Station Marker (Prominent Glowing Beacon)
            let homePos = cartesianCoordinate(lat: home.latitude, lon: home.longitude, radius: Double(earthRadius + 0.08))
            let homePin = createPinNode(color: .systemGreen, isHome: true, label: "📡 HOME [EP2AES]", flag: "🇮🇷")
            homePin.position = homePos
            markersContainer.addChildNode(homePin)

            // 2. Plot DX Markers & Arcs
            for marker in markers.prefix(35) {
                let dxPos = cartesianCoordinate(lat: marker.coordinate.latitude, lon: marker.coordinate.longitude, radius: Double(earthRadius + 0.08))
                let pinColor = bandColor(marker.band)
                let pinNode = createPinNode(color: pinColor, isHome: false, label: "\(marker.flag) \(marker.callsign)", flag: marker.flag)
                pinNode.position = dxPos
                pinNode.name = marker.id.uuidString
                markerLookup[marker.id.uuidString] = marker
                markersContainer.addChildNode(pinNode)

                // 3. Great Circle 3D Floating Arc
                if showArcs {
                    let waypoints = GeodesicMath.greatCircleWaypoints(from: home, to: marker.coordinate, count: 24)
                    let arcNode = createArcNode(waypoints: waypoints, color: pinColor)
                    arcsContainer.addChildNode(arcNode)
                }
            }

            SCNTransaction.commit()
            scnView?.setNeedsDisplay(scnView?.bounds ?? .zero)
        }

        private func computeSignature(markers: [Globe3DMarker], home: GeoCoordinate, showArcs: Bool) -> String {
            let mSig = markers.prefix(35).map { "\($0.callsign):\($0.band):\($0.mode)" }.joined(separator: ",")
            return "\(home.latitude):\(home.longitude):\(showArcs):\(mSig)"
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView else { return }
            let point = gesture.location(in: scnView)
            let hits = scnView.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])

            for hit in hits {
                var currNode: SCNNode? = hit.node
                while let node = currNode {
                    if let idStr = node.name, let marker = markerLookup[idStr] {
                        parent.onSelectMarker?(marker)
                        return
                    }
                    currNode = node.parent
                }
            }
        }

        // MARK: - 3D Spherical Geometry Mapping (Exact Texture UV Alignment)

        private func cartesianCoordinate(lat: Double, lon: Double, radius: Double) -> SCNVector3 {
            let latRad = lat * .pi / 180.0
            let lonRad = lon * .pi / 180.0

            let x = radius * cos(latRad) * sin(lonRad)
            let y = radius * sin(latRad)
            let z = radius * cos(latRad) * cos(lonRad)
            return SCNVector3(Float(x), Float(y), Float(z))
        }

        private func createPinNode(color: NSColor, isHome: Bool, label: String, flag: String) -> SCNNode {
            let root = SCNNode()

            let cylinder = SCNCylinder(radius: isHome ? 0.12 : 0.07, height: isHome ? 0.40 : 0.28)
            cylinder.firstMaterial?.diffuse.contents = color
            cylinder.firstMaterial?.emission.contents = color.withAlphaComponent(0.7)
            let pinMesh = SCNNode(geometry: cylinder)
            pinMesh.position = SCNVector3(0, Float(cylinder.height / 2.0), 0)
            root.addChildNode(pinMesh)

            let sphere = SCNSphere(radius: isHome ? 0.18 : 0.11)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = SCNVector3(0, Float(cylinder.height), 0)
            root.addChildNode(sphereNode)

            // Billboard text node
            let textGeom = SCNText(string: label, extrusionDepth: 0.02)
            textGeom.font = NSFont.systemFont(ofSize: 0.24, weight: .bold)
            textGeom.firstMaterial?.diffuse.contents = NSColor.white
            let textNode = SCNNode(geometry: textGeom)
            textNode.scale = SCNVector3(0.32, 0.32, 0.32)
            textNode.position = SCNVector3(-0.35, Float(cylinder.height) + 0.18, 0)
            let constraint = SCNBillboardConstraint()
            constraint.freeAxes = .all
            root.constraints = [constraint]
            root.addChildNode(textNode)

            return root
        }

        private func createArcNode(waypoints: [GeoCoordinate], color: NSColor) -> SCNNode {
            let arcRoot = SCNNode()
            guard waypoints.count >= 2 else { return arcRoot }

            let maxElevation: Double = 1.3
            for i in 0..<(waypoints.count - 1) {
                let fraction1 = Double(i) / Double(waypoints.count - 1)
                let fraction2 = Double(i + 1) / Double(waypoints.count - 1)

                let elev1 = sin(fraction1 * .pi) * maxElevation
                let elev2 = sin(fraction2 * .pi) * maxElevation

                let p1 = cartesianCoordinate(lat: waypoints[i].latitude, lon: waypoints[i].longitude, radius: Double(earthRadius) + 0.06 + elev1)
                let p2 = cartesianCoordinate(lat: waypoints[i + 1].latitude, lon: waypoints[i + 1].longitude, radius: Double(earthRadius) + 0.06 + elev2)

                let segNode = lineSegment(from: p1, to: p2, color: color)
                arcRoot.addChildNode(segNode)
            }

            return arcRoot
        }

        private func lineSegment(from p1: SCNVector3, to p2: SCNVector3, color: NSColor) -> SCNNode {
            let vector = SCNVector3(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)
            let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)

            let cylinder = SCNCylinder(radius: 0.028, height: CGFloat(distance))
            cylinder.firstMaterial?.diffuse.contents = color
            cylinder.firstMaterial?.emission.contents = color.withAlphaComponent(0.8)

            let node = SCNNode(geometry: cylinder)
            node.position = SCNVector3((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, (p1.z + p2.z) / 2.0)

            node.eulerAngles = SCNVector3(
                Float(acos(Double(vector.y / distance))),
                Float(atan2(Double(vector.x), Double(vector.z))),
                0
            )
            return node
        }

        private func bandColor(_ band: String) -> NSColor {
            let b = band.uppercased()
            if b == "160M" || b == "80M" { return NSColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1.0) }
            if b == "40M" || b == "30M" { return NSColor(red: 0.98, green: 0.65, blue: 0.20, alpha: 1.0) }
            if b == "20M" || b == "17M" { return NSColor(red: 0.25, green: 0.85, blue: 0.40, alpha: 1.0) }
            if b == "15M" || b == "12M" { return NSColor(red: 0.20, green: 0.70, blue: 0.98, alpha: 1.0) }
            if b == "10M" || b == "6M" { return NSColor(red: 0.80, green: 0.35, blue: 0.98, alpha: 1.0) }
            return NSColor(red: 0.40, green: 0.85, blue: 0.95, alpha: 1.0)
        }

        // MARK: - Earth Texture Generator (Vector Boundaries, Country Names & Flags)

        static func cachedEarthTexture(showLabels: Bool) -> NSImage {
            if let cached = textureCache[showLabels] {
                return cached
            }
            let img = generateEarthTexture(showLabels: showLabels)
            textureCache[showLabels] = img
            return img
        }

        private static func generateEarthTexture(showLabels: Bool) -> NSImage {
            let width = 2048
            let height = 1024
            let img = NSImage(size: NSSize(width: width, height: height))
            img.lockFocus()

            // 1. Deep Oceanic Blue Base
            let oceanColor = NSColor(red: 0.05, green: 0.12, blue: 0.24, alpha: 1.0)
            oceanColor.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()

            // 2. High-Precision Vector Country Boundaries
            let landFill = NSColor(red: 0.14, green: 0.28, blue: 0.24, alpha: 1.0)
            let borderStroke = NSColor(red: 0.28, green: 0.75, blue: 0.65, alpha: 0.9)

            func pt(_ lat: Double, _ lon: Double) -> NSPoint {
                let x = (lon + 180.0) / 360.0 * Double(width)
                let y = (lat + 90.0) / 180.0 * Double(height)
                return NSPoint(x: x, y: y)
            }

            for poly in WorldVectorGeography.countryBoundaries {
                guard poly.coordinates.count >= 3 else { continue }
                let path = NSBezierPath()
                path.lineWidth = 1.8
                path.move(to: pt(poly.coordinates[0].latitude, poly.coordinates[0].longitude))
                for i in 1..<poly.coordinates.count {
                    path.line(to: pt(poly.coordinates[i].latitude, poly.coordinates[i].longitude))
                }
                path.close()
                landFill.setFill()
                path.fill()
                borderStroke.setStroke()
                path.stroke()
            }

            // 3. Country Names & Flag Labels
            if showLabels {
                let labelFont = NSFont.systemFont(ofSize: 11, weight: .bold)
                let textAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: NSColor(white: 0.92, alpha: 0.95)
                ]

                for country in WorldVectorGeography.countries {
                    let p = pt(country.center.latitude, country.center.longitude)
                    let text = "\(country.flag) \(country.name) (\(country.primaryPrefix))"
                    let str = NSAttributedString(string: text, attributes: textAttrs)
                    let strSize = str.size()
                    let rect = NSRect(x: p.x - strSize.width / 2.0, y: p.y - strSize.height / 2.0, width: strSize.width, height: strSize.height)
                    str.draw(in: rect)
                }
            }

            // 4. Latitude & Longitude Coordinate Grid (15° increments)
            let gridColor = NSColor(white: 1.0, alpha: 0.10)
            gridColor.setStroke()
            let gridPath = NSBezierPath()
            gridPath.lineWidth = 1.0

            for lon in stride(from: 0.0, through: Double(width), by: Double(width) / 24.0) {
                gridPath.move(to: NSPoint(x: lon, y: 0))
                gridPath.line(to: NSPoint(x: lon, y: Double(height)))
            }
            for lat in stride(from: 0.0, through: Double(height), by: Double(height) / 12.0) {
                gridPath.move(to: NSPoint(x: 0, y: lat))
                gridPath.line(to: NSPoint(x: Double(width), y: lat))
            }
            gridPath.stroke()

            // Equator & Prime Meridian highlight
            let equatorColor = NSColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 0.35)
            equatorColor.setStroke()
            let eqPath = NSBezierPath()
            eqPath.lineWidth = 1.8
            eqPath.move(to: NSPoint(x: 0, y: Double(height) / 2.0))
            eqPath.line(to: NSPoint(x: Double(width), y: Double(height) / 2.0))
            eqPath.stroke()

            img.unlockFocus()
            return img
        }
    }
}
