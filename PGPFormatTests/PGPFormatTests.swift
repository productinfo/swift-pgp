//
//  PGPFormatTests.swift
//  PGPFormatTests
//
//  Created by Alex Grinman on 5/17/17.
//  Copyright © 2017 KryptCo, Inc. All rights reserved.
//

import XCTest
@testable import PGPFormat

class PGPFormatTests: XCTestCase {
    
    var pubkey1:String!
    override func setUp() {
        super.setUp()
        
        let bundle = Bundle(for: type(of: self))
        let path = bundle.path(forResource: "pubkey1", ofType: "txt")!
        pubkey1 = try! String(contentsOfFile: path)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    //MARK: Ascii Armor
    func testAsciiArmor() {
        do {
            let pubMsg = try AsciiArmorMessage(string: pubkey1)

            if pubMsg.comment != "Some test hello" {
                XCTFail("invalid comment: \(pubMsg.comment)")
            }
            
            if pubMsg.crcChecksum.toBase64() != "m4zw" {
                XCTFail("invalid checksum: \(pubMsg.crcChecksum.toBase64())")
            }
            
            if pubMsg.blockType != ArmorMessageBlock.publicKey {
                XCTFail("invalid block type: \(pubMsg.blockType)")
            }
            
            let pubMsgAgain = try AsciiArmorMessage(string: pubMsg.toString())

        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testChecksum() {
        let data = try! "yDgBO22WxBHv7O8X7O/jygAEzol56iUKiXmV+XmpCtmpqQUKiQrFqclFqUDBovzSvBSFjNSiVHsuAA==".fromBase64()
        
        let check = data.crc24Checksum.toBase64()
        
        guard check == "njUN" else {
            XCTFail("mismatching checksum. got: \(check)")
            return
        }
    }
    
    //MARK: Packets
    
    func testPublicKeySerializeDeserializePacket() {
        do  {
            let pubMsg = try AsciiArmorMessage(string: pubkey1)
            let packets = try [Packet](data: pubMsg.packetData)
            
            for packet in [packets[0], packets[4]] {
                let packetOriginal = packet
                let pubKeyOriginal = try PublicKey(packet: packetOriginal)
                
                let packetSerialized = try pubKeyOriginal.toPacket()
                let pubKeyDeserialized = try PublicKey(packet: packetSerialized)
                
                guard packetSerialized.body == packetOriginal.body else {
                    print("original: \(packetOriginal.body.bytes)")
                    print("serialized: \(packetSerialized.body.bytes)")
                    XCTFail("packets differ after serialization deserialization")
                    return
                    
                }

            }
            
        } catch {
            XCTFail("Unexpected error: \(error)")

        }
    }
    
    func testFingerprintAndKeyId() {
        do  {
            let pubMsg = try AsciiArmorMessage(string: pubkey1)
            let packets = try [Packet](data: pubMsg.packetData)
            
            for packet in [packets[0]] {
                let packetOriginal = packet
                let pubKeyOriginal = try PublicKey(packet: packetOriginal)
                
                let fp = try pubKeyOriginal.fingerprint().hex
                let keyID = try pubKeyOriginal.keyID().hex
                
                guard fp.uppercased() == "F7A83D5CE65C42817A4AB7647A1037F5EF07891E" else {
                    XCTFail("Fingerprint does not match, got: \(fp)")
                    return
                }
                
                guard keyID.uppercased() == "7A1037F5EF07891E" else {
                    XCTFail("KeyID does not match, got: \(keyID)")
                    return
                }

            }
            
        } catch {
            XCTFail("Unexpected error: \(error)")
            
        }
    }

    
    // UserID
    func testUserIDPacket() {
        do  {
            let pubMsg = try AsciiArmorMessage(string: pubkey1)
            let packets = try [Packet](data: pubMsg.packetData)
            
            let packetOriginal = packets[1]
            let userIDOriginal = try UserID(packet: packetOriginal)
            
            let packetSerialized = try userIDOriginal.toPacket()
            let userIDDeserialized = try UserID(packet: packetSerialized)
            
            guard packetSerialized.body == packetOriginal.body else {
                print("original: \(packetOriginal.body.bytes)")
                print("serialized: \(packetSerialized.body.bytes)")
                XCTFail("packets differ after serialization deserialization")
                return
                
            }
            
        } catch {
            XCTFail("Unexpected error: \(error)")
            
        }
    }
    
    // Signature
    func testSignatureSerializeDeserializePacket() {
        do  {
            let pubMsg = try AsciiArmorMessage(string: pubkey1)
            let packets = try [Packet](data: pubMsg.packetData)
            
            for packet in [packets[2], packets[3], packets[5]] {
                let packetOriginal = packet
                let sigOriginal = try Signature(packet: packetOriginal)
                
                let packetSerialized = try sigOriginal.toPacket()
                let sigDeserialized = try Signature(packet: packetSerialized)
                
                guard packetSerialized.body == packetOriginal.body else {
                    print("original: \(packetOriginal.body.bytes)")
                    print("serialized: \(packetSerialized.body.bytes)")
                    XCTFail("packets differ after serialization deserialization")
                    return
                    
                }
            }
            
        } catch {
            XCTFail("Unexpected error: \(error)")
            
        }
    }
    
    // Test public key signature verification
    func testSignatureHashMatchesLeft16Bits() {
        do  {
            let pubMsg = try AsciiArmorMessage(string: pubkey1)
            let packets = try [Packet](data: pubMsg.packetData)
            
            let publicKey = try PublicKey(packet: packets[0])
            let userID = try UserID(packet: packets[1])
            let signature = try Signature(packet: packets[2])
            
            let created = (signature.hashedSubpacketables[0] as! SignatureCreated).date
            let pubKeyToSign = PublicKeyIdentityToSign(publicKey: publicKey, userID: userID, created: created)
            
            let dataToHash = try pubKeyToSign.dataToHash(hashAlgorithm: signature.hashAlgorithm)
            
            var hash:Data

            switch signature.hashAlgorithm {
            case .sha1:
                hash = dataToHash.SHA1
            case .sha224:
                hash = dataToHash.SHA224
            case .sha256:
                hash = dataToHash.SHA256
            case .sha384:
                hash = dataToHash.SHA384
            case .sha512:
                hash = dataToHash.SHA512
            }
            
            let leftTwoBytes = [UInt8](hash.bytes[0...1])
            
            guard leftTwoBytes == signature.leftTwoHashBytes else {
                XCTFail("Left two hash bytes don't match: \nGot: \(leftTwoBytes)\nExpected: \(signature.leftTwoHashBytes)")
                return
            }
            
            
        } catch {
            XCTFail("Unexpected error: \(error)")
            
        }
    }



}