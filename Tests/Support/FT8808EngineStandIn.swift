// Stand-in for the FT8808Engine package, for the behaviour tests of the CAT radio drivers
// (Tests/CATChunkStopRegression.swift). YAAM/Lab599TX500Driver.swift and YAAM/FX4CRDriver.swift import FT8808Engine
// only to list audio devices (AudioDevices); this stand-in lists none, so nothing opens an audio device.
// It is compiled on its own as a module named FT8808Engine (the build command is in the test's header). Only the
// members the two drivers use are declared. Nothing in the app refers to this file.
import Foundation

public struct AudioInputDevice: Sendable {
    public let name: String
    public let uid: String
}

public enum AudioDevices {
    public static func inputDevices() -> [AudioInputDevice] { [] }
    public static func outputDevices() -> [AudioInputDevice] { [] }
}
