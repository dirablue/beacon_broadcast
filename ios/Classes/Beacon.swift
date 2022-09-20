//
//  Beacon.swift
//
//  Created by Paulina Szklarska on 23/01/2019.
//  Copyright © 2019 Paulina Szklarska. All rights reserved.
//

import Foundation
import CoreBluetooth
import CoreLocation

class Beacon: NSObject, CBPeripheralManagerDelegate {

    var peripheralManager: CBPeripheralManager!
    var beaconPeripheralData: NSDictionary!
    var onAdvertisingStateChanged: ((Bool) -> Void)?
    var onCharacteristicReceiveRead: ((BeaconCharacteristic) -> Void)?
    var onCharacteristicReceiveWrite: (([BeaconCharacteristic]) -> Void)?

    var shouldStartAdvertise: Bool = false

    var beaconData: BeaconData?

    func start(beaconData: BeaconData) {
        self.beaconData = beaconData

        let proximityUUID = UUID(uuidString: beaconData.uuid)
        let major: CLBeaconMajorValue = CLBeaconMajorValue(truncating: beaconData.majorId)
        let minor: CLBeaconMinorValue = CLBeaconMinorValue(truncating: beaconData.minorId)
        let beaconID = beaconData.identifier

        let region = CLBeaconRegion(proximityUUID: proximityUUID!,
                                    major: major, minor: minor, identifier: beaconID)

        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

        beaconPeripheralData = region.peripheralData(withMeasuredPower: beaconData.transmissionPower)
        shouldStartAdvertise = true
    }

    func stop() {
        if peripheralManager != nil {
            peripheralManager.stopAdvertising()
            onAdvertisingStateChanged!(false)
        }
    }

    func isAdvertising() -> Bool {
        if peripheralManager == nil {
            return false
        }
        return peripheralManager.isAdvertising
    }

    // event handler END

    func addBeaconServices(services: [BeaconService]?) {
        for service in services ?? [] {
            let mutableService = CBMutableService(
                type: CBUUID(string: service.uuid),
                primary: service.primary ?? false
            )

            var mutableCharacteristics: [CBMutableCharacteristic] = []

            for characteristic in service.characteristics ?? [] {
                let mutableCharacteristic = CBMutableCharacteristic(
                    type: CBUUID(string: characteristic.uuid),
                    properties: characteristic.properties,
                    // NOTE:
                    // set nil always since it will be error if you set the properties except '.read'
                    // for getting real value, using cache object in didReceiveRead method.
                    //
                    // https://developer.apple.com/documentation/corebluetooth/cbmutablecharacteristic/1519073-init
                    // value - The characteristic value to cache. If nil,
                    // the value is dynamic and the peripheral manager fetches it on demand.
                    value: nil, // characteristic.value,
                    permissions: characteristic.permissions
                )
                mutableCharacteristics.append(mutableCharacteristic)
            }

            mutableService.characteristics = mutableCharacteristics
            peripheralManager?.add(mutableService)
        }
    }

    func updateBeaconServices(services: [BeaconService]?) {
        self.beaconData?.services = services

        peripheralManager?.removeAllServices()
        if services != nil {
            addBeaconServices(services: services!)
        }
    }

    // -----------------------------------------------------------------------------------------
    // event handlers
    // https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerdelegate
    // -----------------------------------------------------------------------------------------

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        onAdvertisingStateChanged!(peripheral.isAdvertising)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && shouldStartAdvertise {
            shouldStartAdvertise = false
            peripheralManager.startAdvertising(((beaconPeripheralData as NSDictionary) as! [String: Any]))
            addBeaconServices(services: self.beaconData?.services)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        debugPrint("[didReceiveRead] called")

        let service: BeaconService? = self.beaconData?.services?.first {
            $0.uuid == request.characteristic.service?.uuid.uuidString ?? ""
        }
        if service == nil {
            debugPrint("[didReceiveRead] error: not found service.")
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        let characteristic: BeaconCharacteristic? = service?.characteristics.first {
            $0.uuid == request.characteristic.uuid.uuidString
        }
        if characteristic == nil {
            debugPrint("[didReceiveRead] error: not found characteristic.")
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        debugPrint("[didReceiveRead] success.")
        self.onCharacteristicReceiveRead?(characteristic!)
        request.value = characteristic!.value?.data(using: .utf8)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        debugPrint("[didReceiveWrite] called")
        guard let firstRequest: CBATTRequest = requests.first else {
            return
        }

        var responseCharacteristics: [BeaconCharacteristic] = []

        for request in requests {
            let service: BeaconService? = self.beaconData?.services?.first {
                $0.uuid.uppercased() == (request.characteristic.service?.uuid.uuidString ?? "").uppercased()
            }
            if service == nil {
                debugPrint("[didReceiveWrite] error: not found service.")
                peripheralManager?.respond(to: firstRequest, withResult: .attributeNotFound)
                return
            }

            let characteristic: BeaconCharacteristic? = service?.characteristics.first {
                $0.uuid.uppercased() == request.characteristic.uuid.uuidString.uppercased()
            }
            if characteristic == nil {
                debugPrint("[didReceiveWrite] error: not found characteristic.")
                peripheralManager?.respond(to: firstRequest, withResult: .attributeNotFound)
                return
            }

            var requestValue: String? = request.value != nil ? String(data: request.value!, encoding: .utf8) : nil
            if !self.validateRequestValue(
                validMethod: characteristic?.validMethod,
                validValue: characteristic?.validValue,
                requestValue: requestValue) {
                debugPrint("[didReceiveWrite] error: failed to call validateRequestValue.")
                peripheralManager?.respond(to: firstRequest, withResult: .attributeNotFound)
                return
            }

            characteristic!.value = requestValue
            responseCharacteristics.append(characteristic!)
        }

        debugPrint("[didReceiveWrite] success")

        self.onCharacteristicReceiveWrite?(responseCharacteristics)
        peripheral.respond(to: firstRequest, withResult: .success)
    }

    func validateRequestValue(validMethod: String?, validValue: String?, requestValue: String?) -> Bool {
        print("validateRequestValue validMethod=" + (validMethod ?? "") + ", validValue=" + (validValue ?? "") + ", requestValue=" + (requestValue ?? ""))
        if validMethod != nil && validValue != nil && requestValue != nil {
            if validMethod == "match" {
                return validValue == requestValue
            } else if validMethod == "prefixMatch" {
                return requestValue?.starts(with: validValue ?? "") ?? false
            }
        }
        return false
    }
}

class BeaconData {
    var uuid: String
    var majorId: NSNumber
    var minorId: NSNumber
    var transmissionPower: NSNumber?
    var identifier: String
    var services: [BeaconService]?

    init(uuid: String, majorId: NSNumber, minorId: NSNumber, transmissionPower: NSNumber?, identifier: String,
         services: [BeaconService]?) {

        self.uuid = uuid
        self.majorId = majorId
        self.minorId = minorId
        self.transmissionPower = transmissionPower
        self.identifier = identifier
        self.services = services
    }
}

class BeaconService {
    var uuid: String
    var primary: Bool
    var characteristics: [BeaconCharacteristic]

    init(uuid: String, primary: Bool, characteristics: [BeaconCharacteristic]) {
        self.uuid = uuid
        self.primary = primary
        self.characteristics = characteristics
    }

    class func fromMap(data: [String: Any]) -> BeaconService {
        let service = BeaconService(
            uuid: data["uuid"] as! String,
            primary: data["primary"] as! Bool,
            characteristics: (data["characteristics"] as! [[String: Any]]).map {
                BeaconCharacteristic.fromMap(data: $0)
            }
        )

        return service
    }
}

class BeaconCharacteristic {
    var uuid: String
    var value: String?
    var validMethod: String?
    var validValue: String?
    var properties: CBCharacteristicProperties
    var permissions: CBAttributePermissions

    init(uuid: String,
         value: String?,
         validMethod: String?,
         validValue: String?,
         properties: CBCharacteristicProperties,
         permissions: CBAttributePermissions
    ) {

        self.uuid = uuid
        self.value = value
        self.validMethod = validMethod
        self.validValue = validValue
        self.properties = properties
        self.permissions = permissions
    }

    class func fromMap(data: [String: Any]) -> BeaconCharacteristic {
        let service = BeaconCharacteristic(
            uuid: data["uuid"] as! String,
            value: data["value"] as? String,
            validMethod: data["validMethod"] as? String,
            validValue: data["validValue"] as? String,
            properties: CBCharacteristicProperties.fromStringList(
                values: data["properties"] as! [String]
            ),
            permissions: CBAttributePermissions.fromStringList(
                values: data["permissions"] as! [String]
            )
        )
        return service
    }
}

extension String: Error {}

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

enum CustomError: Error {
    case invalidParameterError(String)
}

extension CBCharacteristicProperties {
    static func fromString(value: String) -> CBCharacteristicProperties? {
        switch value {
        case "broadcast": return CBCharacteristicProperties.broadcast
        case "read": return CBCharacteristicProperties.read
        case "writeWithoutResponse": return CBCharacteristicProperties.writeWithoutResponse
        case "write": return CBCharacteristicProperties.write
        case "notify": return CBCharacteristicProperties.notify
        case "indicate": return CBCharacteristicProperties.indicate
        case "authenticatedSignedWrites": return CBCharacteristicProperties.authenticatedSignedWrites
        case "extendedProperties": return CBCharacteristicProperties.extendedProperties
        case "notifyEncryptionRequired": return CBCharacteristicProperties.notifyEncryptionRequired
        case "indicateEncryptionRequired": return CBCharacteristicProperties.indicateEncryptionRequired
        default:
            print("Undefined CBCharacteristicProperties type. type=" + value)
            return nil
        }
    }

    static func fromStringList(values: [String]) -> CBCharacteristicProperties {
        return CBCharacteristicProperties(rawValue: values.map {
            CBCharacteristicProperties.fromString(value: $0)?.rawValue ?? 0
        }.reduce(0, |))
    }
}

extension CBAttributePermissions {
    static func fromString(value: String) -> CBAttributePermissions? {
        switch value {
        case "readable": return CBAttributePermissions.readable
        case "writeable": return CBAttributePermissions.writeable
        case "readEncryptionRequired": return CBAttributePermissions.readEncryptionRequired
        case "writeEncryptionRequired": return CBAttributePermissions.writeEncryptionRequired
        default:
            print("Undefined CBAttributePermissions type. type=" + value)
            return nil
        }
    }

    static func fromStringList(values: [String]) -> CBAttributePermissions {
        return CBAttributePermissions(rawValue: values.map {
            CBAttributePermissions.fromString(value: $0)?.rawValue ?? 0
        }.reduce(0, |))
    }
}
