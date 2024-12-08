//
//  ZMQHandler.swift
//  WarDragon
//
//  Created by Luke on 12/6/24.
//

import Foundation
import SwiftyZeroMQ5

// MARK: - ZMQ Handler
final class ZMQHandler {
    // MARK: - Properties
    @Published var isConnected = false {
        didSet {
            if oldValue != isConnected {
                DispatchQueue.main.async {
                    Settings.shared.isListening = self.isConnected
                }
            }
        }
    }

    private var context: SwiftyZeroMQ.Context?
    private var telemetrySocket: SwiftyZeroMQ.Socket?
    private var statusSocket: SwiftyZeroMQ.Socket?
    private var telemetryPoller: SwiftyZeroMQ.Poller?
    private var statusPoller: SwiftyZeroMQ.Poller?
    private var shouldContinueRunning = false
    private let processor = ZMQMessageProcessor()
    private let reconnectInterval: TimeInterval = 5.0
    private var reconnectTimer: Timer?

    // MARK: - Socket Configuration
    private struct SocketConfig {
        static let timeout: Int32 = 1000
        static let highWaterMark: Int32 = 1000
        static let bufferSize: Int = 65536
    }

    // MARK: - Public Methods
    func connect(
        host: String,
        zmqTelemetryPort: UInt16,
        zmqStatusPort: UInt16,
        onTelemetry: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        guard !isConnected else { return }
        
        disconnect()
        shouldContinueRunning = true
        
        do {
            context = try SwiftyZeroMQ.Context()
            try setupSockets(host: host, telemetryPort: zmqTelemetryPort, statusPort: zmqStatusPort)
            startPolling(onTelemetry: onTelemetry, onStatus: onStatus)
            isConnected = true
            startReconnectTimer()
        } catch {
            print("ZMQ Setup Error: \(error)")
            scheduleReconnect(host: host, telemetryPort: zmqTelemetryPort, statusPort: zmqStatusPort,
                            onTelemetry: onTelemetry, onStatus: onStatus)
        }
    }

    func disconnect() {
        shouldContinueRunning = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        do {
            try telemetrySocket?.close()
            try statusSocket?.close()
            try context?.terminate()
        } catch {
            print("ZMQ Cleanup Error: \(error)")
        }
        
        telemetrySocket = nil
        statusSocket = nil
        context = nil
        telemetryPoller = nil
        statusPoller = nil
        isConnected = false
    }

    // MARK: - Private Methods
    private func setupSockets(host: String, telemetryPort: UInt16, statusPort: UInt16) throws {
        telemetrySocket = try context?.socket(.subscribe)
        statusSocket = try context?.socket(.subscribe)
        
        try configureTelemetrySocket(telemetrySocket!, host: host, port: telemetryPort)
        try configureStatusSocket(statusSocket!, host: host, port: statusPort)
        
        telemetryPoller = SwiftyZeroMQ.Poller()
        statusPoller = SwiftyZeroMQ.Poller()
        
        try telemetryPoller?.register(socket: telemetrySocket!, flags: .pollIn)
        try statusPoller?.register(socket: statusSocket!, flags: .pollIn)
    }

    private func configureTelemetrySocket(_ socket: SwiftyZeroMQ.Socket, host: String, port: UInt16) throws {
        try socket.setSubscribe("")
        try socket.setImmediate(true)
        try socket.setRecvTimeout(SocketConfig.timeout)
        try socket.setReconnectInterval(Int32(reconnectInterval * 1000))
        try socket.setRecvHighWaterMark(SocketConfig.highWaterMark)
        try socket.connect("tcp://\(host):\(port)")
    }

    private func configureStatusSocket(_ socket: SwiftyZeroMQ.Socket, host: String, port: UInt16) throws {
        try socket.setSubscribe("")
        try socket.setImmediate(true)
        try socket.setRecvTimeout(SocketConfig.timeout)
        try socket.setReconnectInterval(Int32(reconnectInterval * 1000))
        try socket.setRecvHighWaterMark(SocketConfig.highWaterMark)
        try socket.connect("tcp://\(host):\(port)")
    }

    private func startPolling(onTelemetry: @escaping (String) -> Void, onStatus: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while self?.shouldContinueRunning == true {
                self?.pollTelemetry(onTelemetry)
                self?.pollStatus(onStatus)
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    private func pollTelemetry(_ handler: @escaping (String) -> Void) {
        do {
            if let items = try telemetryPoller?.poll(timeout: 0.1) {
                for (socket, events) in items where events.contains(.pollIn) {
                    if let data = try socket.recv(bufferLength: SocketConfig.bufferSize),
                       let message = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            if let processed = self.processor.processTelemetryMessage(message) {
                                handler(processed)
                            }
                        }
                    }
                }
            }
        } catch let error as SwiftyZeroMQ.ZeroMQError {
            if error.description != "Resource temporarily unavailable" && shouldContinueRunning {
                print("Telemetry polling error: \(error)")
            }
        } catch {
            if shouldContinueRunning {
                print("Unexpected telemetry error: \(error)")
            }
        }
    }

    private func pollStatus(_ handler: @escaping (String) -> Void) {
        do {
            if let items = try statusPoller?.poll(timeout: 0.1) {
                for (socket, events) in items where events.contains(.pollIn) {
                    if let data = try socket.recv(bufferLength: SocketConfig.bufferSize),
                       let message = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            if let processed = self.processor.processStatusMessage(message) {
                                handler(processed)
                            }
                        }
                    }
                }
            }
        } catch let error as SwiftyZeroMQ.ZeroMQError {
            if error.description != "Resource temporarily unavailable" && shouldContinueRunning {
                print("Status polling error: \(error)")
            }
        } catch {
            if shouldContinueRunning {
                print("Unexpected status error: \(error)")
            }
        }
    }

    private func startReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: true) { [weak self] _ in
            if self?.shouldContinueRunning == true {
                try? self?.telemetrySocket?.setReconnectInterval(Int32(self?.reconnectInterval ?? 5 * 1000))
                try? self?.statusSocket?.setReconnectInterval(Int32(self?.reconnectInterval ?? 5 * 1000))
            }
        }
    }

    private func scheduleReconnect(
        host: String,
        telemetryPort: UInt16,
        statusPort: UInt16,
        onTelemetry: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectInterval) { [weak self] in
            self?.connect(host: host,
                         zmqTelemetryPort: telemetryPort,
                         zmqStatusPort: statusPort,
                         onTelemetry: onTelemetry,
                         onStatus: onStatus)
        }
    }

    // MARK: - Lifecycle
    deinit {
        disconnect()
    }
}
