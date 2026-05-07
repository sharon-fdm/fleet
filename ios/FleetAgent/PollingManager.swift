import Foundation
import BackgroundTasks

/// Manages periodic polling of Fleet server for orbit config and distributed queries.
/// Runs in foreground via Timer and in background via BGAppRefreshTask.
@MainActor
class PollingManager: ObservableObject {
    static let bgTaskIdentifier = "com.fleetdm.agent.poll"

    @Published var lastPollTime: Date?
    @Published var pollCount: Int = 0
    @Published var lastError: String?
    @Published var isPolling: Bool = false
    @Published var lastConfig: OrbitConfigResponse?
    @Published var lastQueryResults: [String: QueryExecutionResult] = [:]
    @Published var policyResults: [PolicyResult] = []

    private var foregroundTimer: Timer?
    let foregroundInterval: TimeInterval = 15
    private let acceleratedInterval: TimeInterval = 5
    private var accelerateRemaining: Int = 0

    let apiClient: ApiClient
    let configManager: ConfigurationManager
    let queryEngine: QueryEngine
    let scheduleManager: ScheduleManager

    init(apiClient: ApiClient, configManager: ConfigurationManager, queryEngine: QueryEngine = QueryEngine(), scheduleManager: ScheduleManager? = nil) {
        self.apiClient = apiClient
        self.configManager = configManager
        self.queryEngine = queryEngine
        self.scheduleManager = scheduleManager ?? ScheduleManager(apiClient: apiClient, configManager: configManager)
    }

    // MARK: - Foreground Polling

    func startForegroundPolling() {
        guard foregroundTimer == nil else { return }
        Task { await performPollCycle() }
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: foregroundInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performPollCycle()
            }
        }
        print("[Fleet] Foreground polling started (every \(Int(foregroundInterval))s)")
    }

    func stopForegroundPolling() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        accelerateRemaining = 0
    }

    /// Restart the foreground timer with a new interval.
    private func restartTimer(interval: TimeInterval) {
        foregroundTimer?.invalidate()
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performPollCycle()
            }
        }
    }

    // MARK: - Background Task

    func scheduleBackgroundPoll() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[Fleet] Background poll scheduled")
        } catch {
            print("[Fleet] Failed to schedule background poll: \(error)")
        }
    }

    func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            print("[Fleet] Background task expired")
        }
        Task {
            await performPollCycle()
            task.setTaskCompleted(success: lastError == nil)
        }
    }

    // MARK: - Poll Cycle

    /// Full poll cycle: fetch config, fetch queries, execute, submit results.
    func performPollCycle() async {
        guard case .enrolled = apiClient.enrollmentState else { return }
        guard !isPolling else { return }

        // Enforce minimum 5s between polls to prevent runaway polling
        if let last = lastPollTime, Date().timeIntervalSince(last) < 5 { return }

        isPolling = true
        defer { isPolling = false }

        do {
            // Step 1: Fetch orbit config
            let config = try await apiClient.withReenrollOnUnauthorized(config: configManager) {
                try await self.apiClient.getOrbitConfig(config: self.configManager)
            }
            lastConfig = config

            // Step 2: Fetch osquery config (scheduled queries) and run due ones
            await scheduleManager.fetchConfig()
            await scheduleManager.runDueQueries()

            // Step 3: Fetch distributed queries
            var pendingQueries: [String: String] = [:]
            do {
                let result = try await apiClient.withReenrollOnUnauthorized(config: configManager) {
                    try await self.apiClient.getDistributedQueries(config: self.configManager)
                }
                pendingQueries = result.queries

                // Accelerated checkin: server asks us to poll faster (e.g. after enrollment)
                if result.accelerate > 0 && accelerateRemaining == 0 {
                    accelerateRemaining = result.accelerate
                    restartTimer(interval: acceleratedInterval)
                    print("[Fleet] Accelerated checkin: \(result.accelerate) fast polls")
                } else if accelerateRemaining > 0 {
                    accelerateRemaining -= 1
                    if accelerateRemaining == 0 {
                        restartTimer(interval: foregroundInterval)
                        print("[Fleet] Accelerated checkin complete, back to \(Int(foregroundInterval))s")
                    }
                }
            } catch {
                print("[Fleet] Distributed query fetch skipped: \(error)")
            }

            // Step 4: Execute queries and collect results
            if !pendingQueries.isEmpty {
                let executionResults = executeQueries(pendingQueries)
                lastQueryResults = executionResults

                // Extract policy results for "My Device" view
                updatePolicyResults(from: executionResults)

                // Step 5: Submit results
                try await submitResults(executionResults)
            }

            lastPollTime = Date()
            pollCount += 1
            lastError = nil

            let queryInfo = pendingQueries.isEmpty ? "" : " — executed \(pendingQueries.count) queries"
            print("[Fleet] Poll #\(pollCount) complete\(queryInfo)")
        } catch {
            lastError = error.localizedDescription
            print("[Fleet] Poll failed: \(error)")
        }

        scheduleBackgroundPoll()
    }

    // MARK: - Query Execution

    /// Execute each distributed query through the QueryEngine.
    func executeQueries(_ queries: [String: String]) -> [String: QueryExecutionResult] {
        var results: [String: QueryExecutionResult] = [:]

        for (name, sql) in queries {
            let rows = queryEngine.execute(sql)
            if queryEngine.parseTableName(sql) != nil {
                results[name] = QueryExecutionResult(rows: rows, status: 0, message: "")
                print("[Fleet] Executed query '\(name)': \(rows.count) rows")
            } else {
                results[name] = QueryExecutionResult(rows: [], status: 1, message: "Could not parse table name")
                print("[Fleet] Query '\(name)' failed: could not parse table name from: \(sql)")
            }
        }

        return results
    }

    /// Submit query results to Fleet server.
    private func submitResults(_ results: [String: QueryExecutionResult]) async throws {
        var queryResults: [String: [TableRow]] = [:]
        var statuses: [String: Int] = [:]
        var messages: [String: String] = [:]

        for (name, result) in results {
            queryResults[name] = result.rows
            statuses[name] = result.status
            messages[name] = result.message
        }

        try await apiClient.withReenrollOnUnauthorized(config: configManager) {
            try await self.apiClient.submitDistributedResults(
                config: self.configManager,
                results: queryResults,
                statuses: statuses,
                messages: messages
            )
        }
        print("[Fleet] Submitted results for \(results.count) queries")
    }

    // MARK: - Policy Tracking

    /// Extract policy pass/fail from distributed query results.
    private func updatePolicyResults(from results: [String: QueryExecutionResult]) {
        var policies: [PolicyResult] = []

        for (name, result) in results {
            guard name.hasPrefix("fleet_policy_query_") else { continue }
            let policyID = String(name.dropFirst("fleet_policy_query_".count))
            let passing = result.status == 0 && !result.rows.isEmpty
            policies.append(PolicyResult(id: policyID, passing: passing))
        }

        if !policies.isEmpty {
            policyResults = policies.sorted { $0.id < $1.id }
            print("[Fleet] Policies: \(policies.filter { $0.passing }.count)/\(policies.count) passing")
        }
    }
}

/// Result of executing a single distributed query.
struct QueryExecutionResult {
    let rows: [TableRow]
    let status: Int       // 0 = success, 1 = error
    let message: String   // Error message (empty on success)
}

/// Policy compliance result.
struct PolicyResult: Identifiable {
    let id: String        // Policy ID
    let passing: Bool
}
