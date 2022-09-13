import Flutter
import UIKit
import Foundation
import CoreBluetooth
import CoreLocation

public class SwiftBeaconBroadcastPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var beacon = Beacon()
    private var advertisingStateChangeEventSink: FlutterEventSink?
    private var characteristicReceiveReadEventSink: FlutterEventSink?
    private var characteristicReceiveWriteEventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftBeaconBroadcastPlugin()

        let channel = FlutterMethodChannel(name: "pl.pszklarska.beaconbroadcast/beacon_state", binaryMessenger: registrar.messenger())

        var beaconEventChannel = FlutterEventChannel(name: BeaconEventChannelType.advertisingStateChange.name, binaryMessenger: registrar.messenger())
        beaconEventChannel.setStreamHandler(instance)

        beaconEventChannel = FlutterEventChannel(name: BeaconEventChannelType.characteristicReceiveRead.name, binaryMessenger: registrar.messenger())
        beaconEventChannel.setStreamHandler(instance)

        beaconEventChannel = FlutterEventChannel(name: BeaconEventChannelType.characteristicReceiveWrite.name, binaryMessenger: registrar.messenger())
        beaconEventChannel.setStreamHandler(instance)

        instance.registerBeaconListener()

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink: @escaping FlutterEventSink) -> FlutterError? {
        switch arguments as? String {
        case BeaconEventChannelType.advertisingStateChange.id:
            self.advertisingStateChangeEventSink = eventSink
        case BeaconEventChannelType.characteristicReceiveRead.id:
            self.characteristicReceiveReadEventSink = eventSink
        case BeaconEventChannelType.characteristicReceiveWrite.id:
            self.characteristicReceiveWriteEventSink = eventSink
        default:
            break
        }

        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        switch arguments as? String {
        case BeaconEventChannelType.advertisingStateChange.id:
            self.advertisingStateChangeEventSink = nil
        case BeaconEventChannelType.characteristicReceiveRead.id:
            self.characteristicReceiveReadEventSink = nil
        case BeaconEventChannelType.characteristicReceiveWrite.id:
            self.characteristicReceiveWriteEventSink = nil
        default:
            break
        }
        return nil
    }

    func registerBeaconListener() {
        beacon.onAdvertisingStateChanged = {isAdvertising in
            if self.advertisingStateChangeEventSink != nil {
                self.advertisingStateChangeEventSink!(isAdvertising)
            }
        }
        beacon.onCharacteristicReceiveRead = {(characteristic: BeaconCharacteristic) in
            if self.characteristicReceiveReadEventSink != nil {
                let data: [String: Any?] = [
                    "uuid": characteristic.uuid,
                    "value": characteristic.value
                ]
                self.characteristicReceiveReadEventSink!(data)
            }
        }
        beacon.onCharacteristicReceiveWrite = {(characteristic: BeaconCharacteristic) in
            if self.characteristicReceiveWriteEventSink != nil {
                let data: [String: Any?] = [
                    "uuid": characteristic.uuid,
                    "value": characteristic.value
                ]
                self.characteristicReceiveWriteEventSink!(data)
            }
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startBeacon(call, result)
        case "stop":
            stopBeacon(call, result)
        case "isAdvertising":
            isAdvertising(call, result)
        case "isTransmissionSupported":
            isTransmissionSupported(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startBeacon(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        var map = call.arguments as? [String: Any]

        let servicesMap = map?["services"] as? [[String: Any]]
        let services = servicesMap?.map { BeaconService.fromMap(data: $0) }

        let beaconData = BeaconData(
            uuid: map?["uuid"] as! String,
            majorId: map?["majorId"] as! NSNumber,
            minorId: map?["minorId"] as! NSNumber,
            transmissionPower: map?["transmissionPower"] as? NSNumber,
            identifier: map?["identifier"] as! String,
            services: services as? [BeaconService]
        )
        beacon.start(beaconData: beaconData)
        result(nil)
    }

    private func stopBeacon(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        beacon.stop()
        result(nil)
    }

    private func isAdvertising(_ call: FlutterMethodCall,
                               _ result: @escaping FlutterResult) {
        result(beacon.isAdvertising())
    }

    private func isTransmissionSupported(_ call: FlutterMethodCall,
                                         _ result: @escaping FlutterResult) {
        result(0)
    }
}

class BeaconEventChannelType {
    final let name: String
    final let id: String

    init(name: String, id: String) {
        self.name = name
        self.id = id
    }

    static let advertisingStateChange = BeaconEventChannelType(
        name: "pl.pszklarska.beaconbroadcast/advertising_state_change_beacon_events",
        id: "advertising_state_change"
    )
    static let characteristicReceiveRead = BeaconEventChannelType(
        name: "pl.pszklarska.beaconbroadcast/characteristic_receive_read_beacon_events",
        id: "characteristic_receive_read"
    )
    static let characteristicReceiveWrite = BeaconEventChannelType(
        name: "pl.pszklarska.beaconbroadcast/characteristic_receive_write_beacon_events",
        id: "characteristic_receive_write"
    )
}
