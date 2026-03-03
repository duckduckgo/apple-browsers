//
//  PacketTunnelRelay.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import NetworkExtension
import os.log

/// Bridges `NEPacketTunnelFlow` and WireGuard via direct CGo buffer passing.
///
/// Instead of a socketpair (PoC v1), Swift pushes packets directly into Go via
/// `wgReceivePackets` (batched) and Go pushes packets back via a registered callback.
/// This eliminates N CGo transitions per readPackets batch and N writePackets calls per flush.
///
/// ```
/// OUTBOUND: packetFlow.readPackets() → pack batch → wgReceivePackets [1 CGo call] → Go channels → WireGuard encrypt
/// INBOUND:  WireGuard decrypt → tun.Write() batches → Flush() → callback → unpack → packetFlow.writePackets()
/// ```
final class PacketTunnelRelay: TunnelFileDescriptorProviding {

    /// Function signature matching `wgReceivePackets(handle, buf, totalLen) -> count`.
    typealias ReceivePacketsFunc = (Int32, UnsafeRawPointer, Int32) -> Int32

    /// Function signature matching `wgSetPacketCallback(handle, context, callback)`.
    /// Callback is batch: `(context, buf, totalLen, count) -> Void`.
    typealias SetPacketCallbackFunc = (Int32, UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Int32) -> Void)?) -> Void

    private var tunnelHandle: Int32 = -1
    private var isRunning = false
    private var packetFlowContext: Unmanaged<NEPacketTunnelFlow>?

    /// Reusable buffer for packing outbound batches (avoids allocation per readPackets callback).
    private var outboundBuffer = Data()

    // Pre-allocated NSNumber constants for AF_INET/AF_INET6 (avoid per-packet allocation).
    private static let afInet = NSNumber(value: UInt32(AF_INET))
    private static let afInet6 = NSNumber(value: UInt32(AF_INET6))

    // MARK: - TunnelFileDescriptorProviding

    /// Returns a dummy fd. With ChannelTun, `wgTurnOn` ignores the fd parameter.
    func currentFileDescriptor() -> Int32? {
        return 0
    }

    // MARK: - Relay

    func start(packetFlow: NEPacketTunnelFlow,
               tunnelHandle: Int32,
               receivePackets: @escaping ReceivePacketsFunc,
               setPacketCallback: @escaping SetPacketCallbackFunc) {
        // Release any previous context on reconnection
        stop()

        self.tunnelHandle = tunnelHandle
        self.isRunning = true
        Logger.networkProtection.log("🦆 [Relay] Starting packet relay (batch channel mode, handle=\(tunnelHandle))")

        startIncomingRelay(packetFlow: packetFlow, tunnelHandle: tunnelHandle, setPacketCallback: setPacketCallback)
        startOutgoingRelay(packetFlow: packetFlow, tunnelHandle: tunnelHandle, receivePackets: receivePackets)
    }

    func stop() {
        isRunning = false
        tunnelHandle = -1
        packetFlowContext?.release()
        packetFlowContext = nil
    }

    // MARK: - Outgoing (packetFlow → wgReceivePackets → WireGuard)

    private func startOutgoingRelay(packetFlow: NEPacketTunnelFlow,
                                    tunnelHandle: Int32,
                                    receivePackets: @escaping ReceivePacketsFunc) {
        func readLoop() {
            packetFlow.readPackets { [weak self] packets, _ in
                guard let self, self.isRunning else { return }
                guard !packets.isEmpty else {
                    readLoop()
                    return
                }

                // Calculate total size needed: 2 bytes length prefix per packet + packet data
                let totalSize = packets.reduce(0) { $0 + 2 + $1.count }
                self.outboundBuffer.count = 0
                self.outboundBuffer.reserveCapacity(totalSize)

                for packet in packets {
                    // Append 2-byte little-endian length prefix
                    var len = UInt16(packet.count)
                    withUnsafeBytes(of: &len) { self.outboundBuffer.append(contentsOf: $0) }
                    self.outboundBuffer.append(packet)
                }

                self.outboundBuffer.withUnsafeBytes { buf in
                    guard let baseAddress = buf.baseAddress else { return }
                    _ = receivePackets(tunnelHandle, baseAddress, Int32(buf.count))
                }

                readLoop()
            }
        }
        readLoop()
    }

    // MARK: - Incoming (WireGuard → callback → packetFlow)

    private func startIncomingRelay(packetFlow: NEPacketTunnelFlow,
                                    tunnelHandle: Int32,
                                    setPacketCallback: @escaping SetPacketCallbackFunc) {
        // Retain the packetFlow in an opaque context so the C callback can reach it.
        let retained = Unmanaged.passRetained(packetFlow)
        packetFlowContext = retained
        let context = retained.toOpaque()

        setPacketCallback(tunnelHandle, context) { ctx, buf, totalLen, count in
            guard let ctx, let buf, totalLen > 0, count > 0 else { return }

            let flow = Unmanaged<NEPacketTunnelFlow>.fromOpaque(ctx).takeUnretainedValue()

            var packets = [Data]()
            var protocols = [NSNumber]()
            packets.reserveCapacity(Int(count))
            protocols.reserveCapacity(Int(count))

            var offset = 0
            let total = Int(totalLen)
            let ptr = buf.assumingMemoryBound(to: UInt8.self)

            while offset + 2 <= total {
                let packetLen = Int(ptr[offset]) | (Int(ptr[offset + 1]) << 8) // LE uint16
                offset += 2

                guard offset + packetLen <= total else { break } // corruption guard

                let packet = Data(bytes: ptr + offset, count: packetLen)
                offset += packetLen

                // Determine AF from IP version header
                let ipVersion = packet[0] >> 4
                let afNumber = (ipVersion == 6) ? PacketTunnelRelay.afInet6 : PacketTunnelRelay.afInet
                packets.append(packet)
                protocols.append(afNumber)
            }

            if !packets.isEmpty {
                flow.writePackets(packets, withProtocols: protocols)
            }
        }
    }
}
