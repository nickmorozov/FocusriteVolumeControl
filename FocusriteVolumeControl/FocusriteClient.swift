//
//  FocusriteClient.swift
//  FocusriteVolumeControl
//
//  TCP client for Focusrite Control Protocol
//

import Foundation
import Network
import Combine

/// Focusrite Control Protocol client
/// Connects to the FocusriteControlServer daemon and communicates via XML messages
class FocusriteClient: ObservableObject {

    // MARK: - Published State

    @Published var isConnected = false
    @Published var isApproved = false
    @Published var deviceModel: String?
    @Published var connectionStatus: String = "Disconnected"

    // MARK: - Device Items

    @Published var items: [String: DeviceItem] = [:]

    // MARK: - Private Properties

    private var connection: NWConnection?
    private var clientId: String?
    private var deviceId: String?
    private let clientKey: String
    private let hostname: String

    private var keepAliveTimer: Timer?
    private var buffer = Data()

    // Discovered or fallback ports
    private var portsToTry: [UInt16] = []
    private var currentPortIndex = 0

    // Fallback ports if discovery fails (common Focusrite Control ports)
    // 58323 seems to be the control protocol, 58322 may be something else
    private let fallbackPorts: [UInt16] = [58323, 58322, 49152, 30096]

    // MARK: - Callbacks

    var onVolumeChange: ((String, Double) -> Void)?
    var onDeviceConnected: (() -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Initialization

    init(clientKey: String? = nil, hostname: String = "FocusriteVolumeControl") {
        // Use a simple numeric key like the original Focusrite Midi Control app
        self.clientKey = clientKey ?? "987654321"
        self.hostname = hostname
    }

    // MARK: - Connection Management

    func connect() {
        // Discover ports from running Focusrite process
        discoverPorts { [weak self] ports in
            guard let self = self else { return }

            if ports.isEmpty {
                DispatchQueue.main.async {
                    self.connectionStatus = "Focusrite Control not running"
                    self.onError?("Could not find Focusrite Control process. Make sure Focusrite Control 2 is running.")
                }
                return
            }

            self.portsToTry = ports
            self.currentPortIndex = 0
            self.tryNextPort()
        }
    }

    /// Discover Focusrite listening ports using lsof
    private func discoverPorts(completion: @escaping ([UInt16]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ports: [UInt16] = []

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            // Find TCP listening ports for Focusrite processes owned by current user
            process.arguments = ["-i", "TCP", "-s", "TCP:LISTEN", "-n", "-P"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("lsof output length: \(output.count) bytes")

                    // Parse lsof output for Focusrite processes
                    // Format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                    // Example: Focusrite  3624 nick   13u  IPv4 ... TCP *:58322 (LISTEN)
                    let currentUser = NSUserName()

                    for line in output.components(separatedBy: "\n") {
                        // Look for Focusrite process owned by current user
                        if line.contains("Focusrite") && line.contains(currentUser) {
                            // Extract port - look for *:PORT or localhost:PORT pattern
                            // Split by whitespace and find the part with the port
                            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                            for part in parts {
                                if part.contains(":") && part.contains("*") {
                                    // Found "*:58322" pattern
                                    let portParts = part.components(separatedBy: ":")
                                    if portParts.count >= 2,
                                       let port = UInt16(portParts[1]) {
                                        ports.append(port)
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Failed to run lsof: \(error)")
            }

            // Remove duplicates and sort in descending order (higher ports first)
            // 58323 seems to be the control protocol, 58322 may be something else
            var uniquePorts = Array(Set(ports)).sorted(by: >)

            // Use fallbacks if discovery failed
            if uniquePorts.isEmpty {
                print("Port discovery returned empty, using fallback ports")
                uniquePorts = self.fallbackPorts.map { $0 }
            } else {
                print("Discovered Focusrite ports: \(uniquePorts)")
            }

            DispatchQueue.main.async {
                completion(uniquePorts)
            }
        }
    }

    private func tryNextPort() {
        guard currentPortIndex < portsToTry.count else {
            print("No more ports to try")
            DispatchQueue.main.async {
                self.connectionStatus = "No server found"
                self.onError?("Could not find Focusrite Control server")
            }
            return
        }

        let port = portsToTry[currentPortIndex]
        print("Attempting connection to port \(port)...")
        DispatchQueue.main.async {
            self.connectionStatus = "Trying port \(port)..."
        }

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        connection = NWConnection(to: endpoint, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, port: port)
        }

        connection?.start(queue: .global(qos: .userInitiated))
    }

    private func handleConnectionState(_ state: NWConnection.State, port: UInt16) {
        print("Connection state on port \(port): \(state)")

        switch state {
        case .ready:
            print("✓ Connected to port \(port)!")
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectionStatus = "Connected (port \(port))"
            }
            startReceiving()
            sendClientDetails()
            startKeepAlive()

        case .failed(let error):
            print("✗ Connection failed on port \(port): \(error)")
            connection?.cancel()
            currentPortIndex += 1
            tryNextPort()

        case .cancelled:
            print("Connection cancelled on port \(port)")
            DispatchQueue.main.async {
                self.isConnected = false
                self.isApproved = false
            }
            stopKeepAlive()

        case .waiting(let error):
            print("Connection waiting on port \(port): \(error)")
            connection?.cancel()
            currentPortIndex += 1
            tryNextPort()

        case .setup:
            print("Connection setup on port \(port)")

        case .preparing:
            print("Connection preparing on port \(port)")

        @unknown default:
            print("Unknown connection state on port \(port)")
        }
    }

    func disconnect() {
        stopKeepAlive()
        connection?.cancel()
        connection = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.isApproved = false
            self.connectionStatus = "Disconnected"
            self.items.removeAll()
        }
    }

    // MARK: - Message Handling

    private func startReceiving() {
        print("Starting receive loop...")
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            print("Receive callback: data=\(data?.count ?? 0) bytes, isComplete=\(isComplete), error=\(String(describing: error))")

            if let data = data, !data.isEmpty {
                print("Raw data received: \(String(data: data.prefix(100), encoding: .utf8) ?? "non-utf8")")
                self?.handleReceivedData(data)
            }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if !isComplete {
                self?.startReceiving()
            } else {
                print("Connection complete (EOF)")
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        buffer.append(data)

        while buffer.count >= 14 {
            guard let headerString = String(data: buffer.prefix(14), encoding: .utf8),
                  headerString.hasPrefix("Length=") else {
                // Invalid data, try to find next Length=
                if let range = buffer.range(of: "Length=".data(using: .utf8)!) {
                    buffer.removeSubrange(0..<range.lowerBound)
                } else {
                    buffer.removeAll()
                }
                break
            }

            let hexLength = headerString.dropFirst(7).dropLast(1) // Remove "Length=" and trailing space
            guard let messageLength = Int(hexLength, radix: 16) else {
                buffer.removeFirst(14)
                continue
            }

            let totalLength = 14 + messageLength
            guard buffer.count >= totalLength else {
                break // Wait for more data
            }

            let messageData = buffer.subdata(in: 14..<totalLength)
            buffer.removeFirst(totalLength)

            if let message = String(data: messageData, encoding: .utf8) {
                handleMessage(message)
            }
        }
    }

    private func handleMessage(_ xml: String) {
        // Debug: print all received messages
        print("Received message: \(xml.prefix(200))...")

        // Parse XML manually (simple parsing for this protocol)
        if xml.contains("<client-details") {
            if let id = extractAttribute(from: xml, name: "id") {
                clientId = id
                print("Client registered with ID: \(id)")
            }
        }
        else if xml.contains("<device-arrival") {
            parseDeviceArrival(xml)
        }
        else if xml.contains("<device-removal") {
            DispatchQueue.main.async {
                self.deviceModel = nil
                self.deviceId = nil
                self.items.removeAll()
            }
        }
        else if xml.contains("<approval") {
            if let authorised = extractAttribute(from: xml, name: "authorised") {
                let isApproved = authorised == "true"
                DispatchQueue.main.async {
                    self.isApproved = isApproved
                    self.connectionStatus = isApproved ? "Connected & Approved" : "Waiting for approval..."
                }
                if isApproved {
                    onDeviceConnected?()
                }
            }
        }
        else if xml.contains("<set") {
            parseValueUpdate(xml)
        }
    }

    // MARK: - XML Parsing Helpers

    private func extractAttribute(from xml: String, name: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }

    private func parseDeviceArrival(_ xml: String) {
        if let model = extractAttribute(from: xml, name: "model"),
           let id = extractAttribute(from: xml, name: "id") {
            deviceId = id

            DispatchQueue.main.async {
                self.deviceModel = model
            }

            // Parse items from device XML
            parseItems(from: xml)

            // Subscribe to device
            subscribeToDevice(id)
        }
    }

    private func parseItems(from xml: String) {
        // Extract all items with id and value attributes
        let pattern = "<[^>]+id=\"([^\"]+)\"[^>]*value=\"([^\"]*)\"[^>]*/?>|<[^>]+value=\"([^\"]*)\"[^>]*id=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }

        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        var newItems: [String: DeviceItem] = [:]

        for match in matches {
            var id: String?
            var value: String?

            // Check both orderings of id/value
            if let range1 = Range(match.range(at: 1), in: xml),
               let range2 = Range(match.range(at: 2), in: xml) {
                id = String(xml[range1])
                value = String(xml[range2])
            } else if let range3 = Range(match.range(at: 3), in: xml),
                      let range4 = Range(match.range(at: 4), in: xml) {
                value = String(xml[range3])
                id = String(xml[range4])
            }

            if let id = id, let value = value {
                newItems[id] = DeviceItem(id: id, value: value)
            }
        }

        DispatchQueue.main.async {
            self.items = newItems
        }
    }

    private func parseValueUpdate(_ xml: String) {
        // Parse <set devid="X"><item id="Y" value="Z"/></set>
        let itemPattern = "<item[^>]+id=\"([^\"]+)\"[^>]*value=\"([^\"]*)\"[^>]*/?>|<item[^>]+value=\"([^\"]*)\"[^>]*id=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: []) else { return }

        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        for match in matches {
            var id: String?
            var value: String?

            if let range1 = Range(match.range(at: 1), in: xml),
               let range2 = Range(match.range(at: 2), in: xml) {
                id = String(xml[range1])
                value = String(xml[range2])
            } else if let range3 = Range(match.range(at: 3), in: xml),
                      let range4 = Range(match.range(at: 4), in: xml) {
                value = String(xml[range3])
                id = String(xml[range4])
            }

            if let id = id, let value = value {
                DispatchQueue.main.async {
                    self.items[id]?.value = value
                    if let numValue = Double(value) {
                        self.onVolumeChange?(id, numValue)
                    }
                }
            }
        }
    }

    // MARK: - Sending Messages

    private func sendMessage(_ content: String) {
        guard let connection = connection else { return }

        // Format: "Length=XXXXXX <xml>" where XXXXXX is hex length of content
        let length = content.count  // Character count, not byte count
        let header = String(format: "Length=%06X ", length)
        let fullMessage = header + content

        print("Full message (\(fullMessage.count) chars): \(fullMessage)")

        let data = fullMessage.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            } else {
                print("Message sent successfully")
            }
        })
    }

    private func sendClientDetails() {
        let msg = "<client-details hostname=\"\(hostname)\" client-key=\"\(clientKey)\"/>"
        print("Sending: \(msg)")
        sendMessage(msg)
    }

    private func subscribeToDevice(_ deviceId: String) {
        let msg = "<device-subscribe devid=\"\(deviceId)\" subscribe=\"true\"/>"
        sendMessage(msg)
    }

    // MARK: - Keep Alive

    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.sendMessage("<keep-alive/>")
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    // MARK: - Control Methods

    func setValue(itemId: String, value: String) {
        guard let deviceId = deviceId, isApproved else {
            print("Cannot set value: not connected or not approved")
            return
        }

        let msg = "<set devid=\"\(deviceId)\"><item id=\"\(itemId)\" value=\"\(value)\"/></set>"
        sendMessage(msg)
    }

    func getItemValue(_ itemId: String) -> Double? {
        guard let item = items[itemId], let value = Double(item.value) else {
            return nil
        }
        return value
    }
}

// MARK: - Device Item Model

struct DeviceItem: Identifiable {
    let id: String
    var value: String
}
