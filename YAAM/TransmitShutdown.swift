//
//  TransmitShutdown.swift
//  YAAM
//
//  Every path that can key a radio registers, when it is created, how to tell whether it is transmitting and how to
//  release it, so that quitting YAAM can release them all in one place (Y-001). Registering changes nothing by itself;
//  shutdown stops producers before releasing transports.
//
//  Platform: pure Swift, no AppKit or serial APIs, so it can be shared with an iPad or iPhone version.
//

import Foundation

enum TransmitShutdown {
    private struct Entry {
        let name: String
        let isTransmitting: () -> Bool
        let release: () -> Void
        let producer: Bool
        weak var owner: AnyObject?
        let hasOwner: Bool
    }

    private(set) static var isShuttingDown = false

    static private(set) var releaseReason = "YAAM is quitting"

    private static var entries: [Entry] = []

    /// Registers a path that can key a radio. Use weak references in the closures: a path that is gone reports false.
    static func register(_ name: String, isTransmitting: @escaping () -> Bool, producer: Bool = false, owner: AnyObject? = nil, release: @escaping () -> Void) {
        entries.removeAll { $0.hasOwner && $0.owner == nil }
        entries.append(Entry(name: name, isTransmitting: isTransmitting, release: release, producer: producer, owner: owner, hasOwner: owner != nil))
    }

    /// The names of the paths transmitting now.
    static var transmitting: [String] { entries.filter { $0.isTransmitting() }.map(\.name) }

    static func beginShutdown() { isShuttingDown = true }

    /// Releases every path that is transmitting now and returns their names. Some releases go over the network or a
    /// queue (TCI closes after its switch-off is sent, up to 2 s; flrig and rigctld send asynchronously): a caller about
    /// to quit has to leave them time.
    @discardableResult
    static func releaseAll(reason: String = "YAAM is quitting") -> [String] {
        releaseReason = reason
        let active = entries.filter { $0.isTransmitting() }
        active.filter(\.producer).forEach { $0.release() }
        active.filter { !$0.producer }.forEach { $0.release() }
        return active.map(\.name)
    }
}
