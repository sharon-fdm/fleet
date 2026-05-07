import SwiftUI

/// "My Device" view showing device info, compliance status, and agent health.
/// Similar to Fleet Desktop on macOS.
struct MyDeviceView: View {
    @EnvironmentObject var apiClient: ApiClient
    @EnvironmentObject var pollingManager: PollingManager
    @Environment(\.dismiss) private var dismiss

    private let queryEngine = QueryEngine()

    var body: some View {
        NavigationStack {
            List {
                deviceSection
                complianceSection
                agentSection
            }
            .navigationTitle("My Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Device Info

    private var deviceSection: some View {
        Section("Device") {
            let deviceInfo = queryEngine.execute("SELECT * FROM device_info").first ?? [:]
            let osVersion = queryEngine.execute("SELECT * FROM os_version").first ?? [:]
            let systemInfo = queryEngine.execute("SELECT * FROM system_info").first ?? [:]

            row("Name", deviceInfo["device_name"] ?? "Unknown")
            row("Model", systemInfo["hardware_model"] ?? deviceInfo["model"] ?? "")
            row("OS", "iOS \(osVersion["version"] ?? "")")
            row("CPU", "\(systemInfo["cpu_type"] ?? "") (\(systemInfo["cpu_physical_cores"] ?? "?") cores)")
            row("Memory", formatBytes(systemInfo["physical_memory"]))

            let disk = queryEngine.execute("SELECT * FROM disk_space").first ?? [:]
            if let avail = disk["gigs_disk_space_available"], let total = disk["gigs_total_disk_space"] {
                row("Disk", "\(avail) GB free / \(total) GB total")
            }

            let battery = queryEngine.execute("SELECT * FROM battery").first ?? [:]
            if let level = battery["level"], level != "-1" {
                row("Battery", "\(level)% (\(battery["state"] ?? ""))")
            }
        }
    }

    // MARK: - Compliance

    private var complianceSection: some View {
        Section("Compliance") {
            let policies = pollingManager.policyResults
            if policies.isEmpty {
                Label("No policies assigned", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            } else {
                let passing = policies.filter { $0.passing }.count
                let total = policies.count
                let allPassing = passing == total

                HStack {
                    Label(
                        allPassing ? "All policies passing" : "\(total - passing) failing",
                        systemImage: allPassing ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                    )
                    .foregroundStyle(allPassing ? .green : .red)
                    Spacer()
                    Text("\(passing)/\(total)")
                        .foregroundStyle(.secondary)
                }

                ForEach(policies) { policy in
                    HStack {
                        Image(systemName: policy.passing ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(policy.passing ? .green : .red)
                        Text("Policy #\(policy.id)")
                        Spacer()
                        Text(policy.passing ? "Pass" : "Fail")
                            .font(.caption)
                            .foregroundStyle(policy.passing ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: - Agent Status

    private var agentSection: some View {
        Section("Agent") {
            let osqueryInfo = queryEngine.execute("SELECT * FROM osquery_info").first ?? [:]
            row("Version", osqueryInfo["version"] ?? "Unknown")

            if case .enrolled = apiClient.enrollmentState {
                row("Status", "Enrolled")
            } else {
                row("Status", "Not Enrolled")
            }

            if let time = pollingManager.lastPollTime {
                row("Last Check-in", formatTime(time))
            }

            row("Poll Count", "\(pollingManager.pollCount)")
            row("Poll Interval", "\(Int(pollingManager.foregroundInterval))s")

            let thermal = queryEngine.execute("SELECT * FROM thermal_state").first ?? [:]
            row("Thermal State", thermal["thermal_state"]?.capitalized ?? "Unknown")

            let uptime = queryEngine.execute("SELECT * FROM uptime").first ?? [:]
            if let days = uptime["days"], let hours = uptime["hours"] {
                row("Uptime", "\(days)d \(hours)h")
            }
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
            .font(.system(.body, design: .default))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: String?) -> String {
        guard let bytes = bytes, let value = UInt64(bytes), value > 0 else { return "Unknown" }
        let gb = Double(value) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }
}
