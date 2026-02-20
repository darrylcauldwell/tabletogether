import Foundation
import Network
import Combine

/// Monitors network connectivity using NWPathMonitor.
/// Provides a shared instance for app-wide network status observation.
@MainActor
final class NetworkMonitor: ObservableObject {

    // MARK: - Shared Instance

    static let shared = NetworkMonitor()

    // MARK: - Published State

    /// Whether the device currently has network connectivity
    @Published private(set) var isConnected: Bool = true

    /// Whether the connection is expensive (cellular/hotspot)
    @Published private(set) var isExpensive: Bool = false

    /// Whether the connection is constrained (low data mode)
    @Published private(set) var isConstrained: Bool = false

    /// The current network interface type
    @Published private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Connection Type

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case wiredEthernet = "Ethernet"
        case loopback = "Loopback"
        case unknown = "Unknown"
    }

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.snap.app.networkmonitor", qos: .utility)

    // MARK: - Initialization

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        // NWPathMonitor.cancel() is thread-safe and can be called from any context
        monitor.cancel()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }

                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained

                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wiredEthernet
                } else if path.usesInterfaceType(.loopback) {
                    self.connectionType = .loopback
                } else {
                    self.connectionType = .unknown
                }

                // Log connectivity changes
                if wasConnected != self.isConnected {
                    if self.isConnected {
                        AppLogger.network.info("Network connected via \(self.connectionType.rawValue)")
                    } else {
                        AppLogger.network.warning("Network disconnected")
                    }
                }
            }
        }

        monitor.start(queue: queue)
        AppLogger.network.debug("Network monitoring started")
    }

    private func stopMonitoring() {
        monitor.cancel()
        AppLogger.network.debug("Network monitoring stopped")
    }

    // MARK: - Convenience Methods

    /// Checks if the network is available for sync operations
    var canSync: Bool {
        isConnected && !isConstrained
    }

    /// Returns a user-friendly description of the current connection
    var connectionDescription: String {
        guard isConnected else {
            return "No connection"
        }

        var parts: [String] = [connectionType.rawValue]

        if isExpensive {
            parts.append("(metered)")
        }

        if isConstrained {
            parts.append("(low data mode)")
        }

        return parts.joined(separator: " ")
    }
}
