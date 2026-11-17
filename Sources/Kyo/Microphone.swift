import CoreAudio

/// Whether some app is recording from a microphone right now, which is the
/// best sign available that the user is in a call. Reading this needs no
/// permission and does not touch the audio itself.
enum Microphone {
    static var isLive: Bool {
        // Only a device that records and does not play (the built-in mic, the
        // mic side of a headset) counts: it runs only when something records.
        // A device that does both also runs for plain playback, and nothing
        // reliable tells the two apart; macOS's per-app "is recording" flag is
        // set by some music players. Missing a call there means a normal
        // reminder. Guessing wrong the other way would silence one.
        objects(kAudioHardwarePropertyDevices).contains {
            flag($0, kAudioDevicePropertyDeviceIsRunningSomewhere)
                && hasStreams($0, .input) && !hasStreams($0, .output)
        }
    }

    private enum Direction {
        case input, output
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The list of devices or of audio-using processes.
    private static func objects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var list = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &list) == noErr
        else { return [] }
        return list
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector)
        -> Bool
    {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
            && value != 0
    }

    private static func hasStreams(_ device: AudioObjectID, _ direction: Direction) -> Bool {
        var address = address(
            kAudioDevicePropertyStreams,
            scope: direction == .input
                ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }
}
