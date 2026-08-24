//
//  BleModuleSpec.swift
//  AppStart Tests
//
//  Release 1：UUID 等价、ACK Matcher、GattProfile merge。

import Quick
import Nimble
import CoreBluetooth
@testable import AppStart

class BleModuleSpec: QuickSpec {

    override class func spec() {

        describe("BleUUID") {
            it("matches 16-bit and standard 128-bit base UUID") {
                let short = CBUUID(string: "AF01")
                let long = CBUUID(string: "0000AF01-0000-1000-8000-00805F9B34FB")
                let alt = CBUUID(string: "00000000-AF01-1000-8000-00805F9B34FB")
                expect(BleUUID.matches(short, long)) == true
                expect(BleUUID.matches(short, alt)) == true
            }

            it("does not match different short UUIDs") {
                let a = CBUUID(string: "AF01")
                let b = CBUUID(string: "AF02")
                expect(BleUUID.matches(a, b)) == false
            }

            it("matches identical 128-bit custom UUIDs") {
                let v3 = CBUUID(string: "524F4F54-9000-0080-0010-000000010001")
                expect(BleUUID.matches(v3, v3)) == true
            }

            it("extracts short16BitKey from base UUID layouts") {
                expect(BleUUID.short16BitKey(from: CBUUID(string: "AF00"))) == "AF00"
                expect(BleUUID.short16BitKey(from: CBUUID(string: "0000AF00-0000-1000-8000-00805F9B34FB"))) == "AF00"
            }
        }

        describe("BleByteAckMatcher") {
            it("compares configured byte indices") {
                let matcher = BleByteAckMatcher(indices: [0, 1, 3])
                let req = Data([0xAA, 0x55, 0x00, 0xC0])
                let partial = Data([0xAA, 0x55, 0x01, 0xC0, 0xFF])
                expect(matcher.matches(command: req, response: partial)) == true
            }
        }

        describe("BleConfiguration merged GattProfile") {
            it("overrides service and characteristic UUIDs") {
                let base = BleConfiguration(
                    gattProfile: BleGattProfile(
                        serviceUUIDs: [CBUUID(string: "AF00")],
                        writeCharUUID: CBUUID(string: "AF01"),
                        notifyCharUUID: CBUUID(string: "AF02")
                    )
                )
                let overlay = BleGattProfile(
                    serviceUUIDs: [CBUUID(string: "524F4F54-9000-0080-0010-000000010001")],
                    writeCharUUID: CBUUID(string: "524F4F54-9000-0080-0010-000000010003"),
                    notifyCharUUID: CBUUID(string: "524F4F54-9000-0080-0010-000000010002")
                )
                let merged = base.merged(with: overlay)
                expect(merged.gattProfile.serviceUUIDs?.first?.uuidString) == overlay.serviceUUIDs?.first?.uuidString
                expect(BleUUID.matches(merged.gattProfile.writeCharUUID!, overlay.writeCharUUID!)) == true
            }

            it("merges from BleProvidesGattProfile parsed data") {
                struct StubProfile: BleProvidesGattProfile {
                    var bleGattProfile: BleGattProfile {
                        BleGattProfile(serviceUUIDs: [CBUUID(string: "BEEF")])
                    }
                }
                let base = BleConfiguration(gattProfile: BleGattProfile(serviceUUIDs: [CBUUID(string: "AF00")]))
                let merged = base.merged(withParsedData: StubProfile())
                expect(BleUUID.matches(merged.gattProfile.serviceUUIDs![0], CBUUID(string: "BEEF"))) == true
            }

            it("merges parser profile into empty base configuration") {
                struct StubProfile: BleProvidesGattProfile {
                    var bleGattProfile: BleGattProfile {
                        BleGattProfile(
                            serviceUUIDs: [CBUUID(string: "AF00")],
                            writeCharUUID: CBUUID(string: "AF01"),
                            notifyCharUUID: CBUUID(string: "AF02")
                        )
                    }
                }
                let merged = BleConfiguration().merged(withParsedData: StubProfile())
                expect(BleUUID.matches(merged.gattProfile.serviceUUIDs![0], CBUUID(string: "AF00"))) == true
                expect(BleUUID.matches(merged.gattProfile.writeCharUUID!, CBUUID(string: "AF01"))) == true
            }
        }
    }
}
