// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import CoreAudio
import Foundation

enum VirtualOutputSupport {
    /// Synchronizes the latest UI request with the serial HAL queue. No lock is
    /// held while calling Core Audio or while dispatching to the main queue.
    final class OutputRequests {
        private let lock = NSLock()
        private var latest = UUID()
        func next() -> UUID {
            lock.lock(); defer { lock.unlock() }
            latest = UUID()
            return latest
        }
        func isCurrent(_ request: UUID) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return latest == request
        }
    }
    static let deviceUID = "VorssaintAudio_UID"
    static let loopbackUID = "VorssaintAudio_2_UID"
    // Compatibility with the local prototype already installed on this Mac.
    // Public builds/installers use Vorssaint Audio exclusively.
    static let legacyDeviceUID = "VorssaintAudioFork_UID"
    static func isSoftwareOutput(_ uid: String?) -> Bool { uid == deviceUID || uid == legacyDeviceUID }
    static func isSoftwareDevice(_ uid: String?) -> Bool { isSoftwareOutput(uid) || uid == loopbackUID }
    static func logicalOutputUID(current: String?, physical: String?, requested: String? = nil) -> String? {
        requested ?? (isSoftwareOutput(current) ? physical : current)
    }
    static func migratedOutputSelection(_ uids: [String], physical: String?) -> [String] {
        var seen = Set<String>()
        return uids.compactMap { uid in
            let target = isSoftwareOutput(uid) ? physical : uid
            guard let target, !target.isEmpty, !isSoftwareDevice(target), seen.insert(target).inserted else { return nil }
            return target
        }
    }
    static let ownerSelector: AudioObjectPropertySelector = 0x766f776e
    static let activeSelector: AudioObjectPropertySelector = 0x76616374

    static func usesVirtualOutput(enabled: Bool, hardwareVolume: Bool) -> Bool { enabled && !hardwareVolume }

    static func restoreUID(current: String?, virtual: String, previous: String?, available: [String], fallback: [String]? = nil, owned: Bool = true) -> String? {
        guard owned, current == virtual else { return nil }
        if let previous, available.contains(previous) { return previous }
        return (fallback ?? available).first
    }

    enum EnableAction { case enable, disable, install }
    static func enableAction(requested: Bool, componentReady: Bool) -> EnableAction {
        if !requested { return .disable }
        return componentReady ? .enable : .install
    }
    enum Issue { case outputUnavailable, setupFailed, privacyUnverified, inUse, stopped, installerMissing, removalFailed }

    enum InputSource { case virtualOutput(streams: Int, physicalStreams: Int), processTap(physicalStreams: Int) }
    static func inputMask(streamCount: Int, source: InputSource) -> [UInt32]? {
        guard streamCount > 0 else { return nil }
        switch source {
        case .virtualOutput(let streams, let physicalStreams):
            guard streams > 0, physicalStreams >= 0, streamCount == streams + physicalStreams else { return nil }
            return (0..<streamCount).map { $0 < streams ? 1 : 0 }
        case .processTap(let physicalStreams):
            guard physicalStreams >= 0, streamCount == physicalStreams + 1 else { return nil }
            return (0..<streamCount).map { $0 == streamCount - 1 ? 1 : 0 }
        }
    }

    /// Layouts are read and validated off the audio thread. Virtual input is
    /// first in the explicitly ordered aggregate, even if hardware has a mic.
    struct RenderPlan {
        struct Channel {
            let buffer: Int
            let channel: Int
            let stride: Int
        }
        let inputChannels: [UInt32]
        let outputChannels: [UInt32]
        let sources: [Channel]
        let targets: [Channel]
        init?(inputChannels: [UInt32], outputChannels: [UInt32], physicalOutputOffset: Int) {
            func channels(_ layout: [UInt32]) -> [Channel] {
                layout.enumerated().flatMap { index, count in
                    (0..<Int(count)).map { Channel(buffer: index, channel: $0, stride: Int(count)) }
                }
            }
            let inputs = channels(inputChannels), outputs = channels(outputChannels)
            guard inputs.count >= 2, physicalOutputOffset >= 0,
                  outputs.count >= physicalOutputOffset + 2 else { return nil }
            self.inputChannels = inputChannels
            self.outputChannels = outputChannels
            sources = Array(inputs.prefix(2))
            targets = Array(outputs.dropFirst(physicalOutputOffset).prefix(2))
        }
        @discardableResult
        func render(input: UnsafeMutableAudioBufferListPointer, output: UnsafeMutableAudioBufferListPointer) -> Bool {
            // Write every output on every path; the virtual pair MUST be zero.
            for buffer in output {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            guard input.count == inputChannels.count, output.count == outputChannels.count else { return false }
            for index in input.indices where input[index].mNumberChannels != inputChannels[index] { return false }
            for index in output.indices where output[index].mNumberChannels != outputChannels[index] { return false }
            var commonFrames = 0
            for index in 0..<2 {
                let source = sources[index], target = targets[index]
                let sourceBytes = Int(input[source.buffer].mDataByteSize)
                let targetBytes = Int(output[target.buffer].mDataByteSize)
                guard input[source.buffer].mData != nil, output[target.buffer].mData != nil,
                      sourceBytes % (4 * source.stride) == 0,
                      targetBytes % (4 * target.stride) == 0 else { return false }
                let frames = min(sourceBytes / (4 * source.stride), targetBytes / (4 * target.stride))
                guard frames > 0, index == 0 || frames == commonFrames else { return false }
                commonFrames = frames
            }
            for index in 0..<2 {
                let source = sources[index], target = targets[index]
                let from = input[source.buffer].mData!.assumingMemoryBound(to: Float.self)
                let to = output[target.buffer].mData!.assumingMemoryBound(to: Float.self)
                for frame in 0..<commonFrames {
                    let value = from[frame * source.stride + source.channel]
                    to[frame * target.stride + target.channel] = value.isFinite ? value : 0
                }
            }
            return true
        }
    }
}
