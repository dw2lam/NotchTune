import Cocoa
import CoreAudio

struct MusicAudioDevice: Hashable, Codable, Identifiable {
    enum AudioError: Swift.Error {
        case invalidDeviceId, invalidDevice, volumeNotSupported, invalidVolumeValue
    }

    let id: AudioDeviceID
    let name: String
    let uid: String
    let isInput: Bool
    let isOutput: Bool
    var transportType: TransportType

    init(withId deviceId: AudioDeviceID) throws {
        self.id = deviceId
        var deviceName = "" as CFString
        var deviceUID = "" as CFString
        do {
            try MusicCoreAudioData.get(id: deviceId, selector: kAudioObjectPropertyName, value: &deviceName)
            try MusicCoreAudioData.get(id: deviceId, selector: kAudioDevicePropertyDeviceUID, value: &deviceUID)
        } catch { throw AudioError.invalidDeviceId }
        self.name = deviceName as String
        self.uid = deviceUID as String

        var rawTransport: UInt32 = 0
        try? MusicCoreAudioData.get(id: deviceId, selector: kAudioDevicePropertyTransportType, value: &rawTransport)
        self.transportType = TransportType(rawTransportType: rawTransport)

        let inputChannels: UInt32 = (try? MusicCoreAudioData.size(id: deviceId, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)) ?? 0
        isInput = inputChannels > 0
        let outputChannels: UInt32 = (try? MusicCoreAudioData.size(id: deviceId, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)) ?? 0
        isOutput = outputChannels > 0
    }

    // MARK: - Static helpers

    static var all: [MusicAudioDevice] {
        guard let devicesSize = try? MusicCoreAudioData.size(selector: kAudioHardwarePropertyDevices) else { return [] }
        let count = Int(devicesSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: count)
        guard (try? MusicCoreAudioData.get(selector: kAudioHardwarePropertyDevices, initialSize: devicesSize, value: &deviceIds)) != nil else { return [] }
        return deviceIds.compactMap { try? MusicAudioDevice(withId: $0) }
    }

    static var output: [MusicAudioDevice] { all.filter { $0.isOutput } }

    static func setDefaultDevice(for deviceType: DeviceType, device: MusicAudioDevice) throws {
        if deviceType.isOutput && !device.isOutput { throw AudioError.invalidDevice }
        var deviceId = device.id
        try MusicCoreAudioData.set(selector: deviceType.selector, value: &deviceId)
    }

    // MARK: - Types

    struct DeviceType {
        let selector: AudioObjectPropertySelector
        let isInput: Bool
        let isOutput: Bool

        static let output = DeviceType(
            selector: kAudioHardwarePropertyDefaultOutputDevice, isInput: false, isOutput: true
        )
    }

    enum TransportType: String, Codable {
        case airplay, bluetooth, bluetoothle, builtin, usb, virtual, unknown

        init(rawTransportType t: UInt32) {
            switch t {
            case kAudioDeviceTransportTypeAirPlay: self = .airplay
            case kAudioDeviceTransportTypeBluetooth: self = .bluetooth
            case kAudioDeviceTransportTypeBluetoothLE: self = .bluetoothle
            case kAudioDeviceTransportTypeBuiltIn: self = .builtin
            case kAudioDeviceTransportTypeUSB: self = .usb
            case kAudioDeviceTransportTypeVirtual: self = .virtual
            default: self = .unknown
            }
        }
    }
}

// MARK: - CoreAudio helpers

private struct MusicCoreAudioData {
    static func get<T>(
        id: UInt32 = AudioObjectID(kAudioObjectSystemObject),
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        initialSize: UInt32 = UInt32(MemoryLayout<T>.size),
        value: UnsafeMutablePointer<T>
    ) throws {
        var size = initialSize
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        try NSError.musicCheckOSStatus { AudioObjectGetPropertyData(id, &address, 0, nil, &size, value) }
    }

    static func set<T>(
        id: UInt32 = AudioObjectID(kAudioObjectSystemObject),
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value: UnsafeMutablePointer<T>
    ) throws {
        let size = UInt32(MemoryLayout<T>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        try NSError.musicCheckOSStatus { AudioObjectSetPropertyData(id, &address, 0, nil, size, value) }
    }

    static func size(
        id: UInt32 = AudioObjectID(kAudioObjectSystemObject),
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> UInt32 {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        try NSError.musicCheckOSStatus { AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) }
        return size
    }
}
