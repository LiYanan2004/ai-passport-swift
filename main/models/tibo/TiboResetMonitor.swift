private struct TiboHTTPResponseBuffer {
    let bytes: UnsafeMutablePointer<CChar>
    let capacity: Int
    var length: Int
    var overflowed: Bool
}

final class TiboResetMonitor {
    static let shared = TiboResetMonitor()

    private static let taskName = StaticString("tibo_reset")
    private static let statusURL = StaticString("https://codex-resets.com/api/v1/status")
    private static let userAgent = StaticString("AI-Passport-Tibo/1.0")
    private static let acceptHeader = StaticString("Accept")
    private static let jsonMediaType = StaticString("application/json")
    private static let responseCapacity = 4_096
    private static let taskStackDepth: UInt32 = 8_192
    private static let taskPriority: UInt32 = 3
    private static let networkWaitMilliseconds: UInt32 = 5_000
    private static let retryIntervalMilliseconds: UInt32 = 60_000
    private static let pollIntervalMilliseconds: UInt32 = 300_000
    private static let maximumPostByteCount = 118

    private var cachedSnapshot = CodexResetQuery.waiting
    private var workerTask: TaskHandle_t?

    private init() {}

    @discardableResult
    func start() -> Bool {
        guard workerTask == nil else { return true }
        var createdTask: TaskHandle_t?
        let result = xTaskCreate(
            swiftTiboResetMonitorTask,
            UnsafePointer<CChar>(OpaquePointer(Self.taskName.utf8Start)),
            Self.taskStackDepth,
            nil,
            Self.taskPriority,
            &createdTask
        )
        guard result == pdPASS else { return false }
        workerTask = createdTask
        return true
    }

    func snapshot() -> CodexResetQuery {
        vPortEnterCritical()
        let snapshot = cachedSnapshot
        vPortExitCritical()
        return snapshot
    }

    func requestRefresh() {
        guard let workerTask else { return }
        passport_task_notify_give(workerTask)
    }

    fileprivate func runWorker() {
        while true {
            guard WiFiConnectionController.shared.connectionState == .connected else {
                wait(milliseconds: Self.networkWaitMilliseconds)
                continue
            }
            let succeeded = refresh()
            wait(milliseconds: succeeded
                ? Self.pollIntervalMilliseconds
                : Self.retryIntervalMilliseconds)
        }
    }

    private func wait(milliseconds: UInt32) {
        let ticks = TickType_t(
            UInt64(milliseconds) * UInt64(CONFIG_FREERTOS_HZ) / 1_000
        )
        _ = passport_task_notify_take(ticks)
    }

    private func refresh() -> Bool {
        let responseBytes = UnsafeMutablePointer<CChar>.allocate(
            capacity: Self.responseCapacity
        )
        responseBytes.initialize(repeating: 0, count: Self.responseCapacity)
        defer { responseBytes.deallocate() }

        let response = UnsafeMutablePointer<TiboHTTPResponseBuffer>.allocate(capacity: 1)
        response.initialize(to: TiboHTTPResponseBuffer(
            bytes: responseBytes,
            capacity: Self.responseCapacity,
            length: 0,
            overflowed: false
        ))
        defer {
            response.deinitialize(count: 1)
            response.deallocate()
        }
        var configuration = esp_http_client_config_t()
        configuration.url = UnsafePointer<CChar>(OpaquePointer(Self.statusURL.utf8Start))
        configuration.user_agent = UnsafePointer<CChar>(OpaquePointer(Self.userAgent.utf8Start))
        configuration.event_handler = swiftTiboHTTPEventHandler
        configuration.user_data = UnsafeMutableRawPointer(response)
        configuration.timeout_ms = 25_000
        configuration.buffer_size = 1_024
        configuration.buffer_size_tx = 512
        configuration.crt_bundle_attach = esp_crt_bundle_attach
        configuration.keep_alive_enable = true

        guard let client = esp_http_client_init(&configuration) else {
            publishError(httpStatus: 0)
            return false
        }
        defer { esp_http_client_cleanup(client) }

        _ = esp_http_client_set_header(
            client,
            UnsafePointer<CChar>(OpaquePointer(Self.acceptHeader.utf8Start)),
            UnsafePointer<CChar>(OpaquePointer(Self.jsonMediaType.utf8Start))
        )
        let requestError = esp_http_client_perform(client)
        let httpStatus = requestError == ESP_OK
            ? Int(esp_http_client_get_status_code(client))
            : 0
        guard requestError == ESP_OK,
              httpStatus == 200,
              !response.pointee.overflowed,
              let nextSnapshot = parseResponse(
                  response.pointee.bytes,
                  length: response.pointee.length,
                  httpStatus: httpStatus
              ) else {
            publishError(httpStatus: httpStatus)
            let errorName = esp_err_to_name(requestError).map { String(cString: $0) } ?? "unknown"
            print("Tibo status refresh failed: error=\(errorName) http=\(httpStatus)")
            return false
        }

        publish(nextSnapshot)
        print("Tibo status refreshed: \(response.pointee.length) bytes")
        return true
    }

    private func parseResponse(
        _ bytes: UnsafePointer<CChar>,
        length: Int,
        httpStatus: Int
    ) -> CodexResetQuery? {
        guard let root = cJSON_ParseWithLength(bytes, length) else { return nil }
        defer { cJSON_Delete(root) }
        guard let data = jsonMember(root, "data"), cJSON_IsObject(data) != 0,
              let stats = jsonMember(data, "stats"), cJSON_IsObject(stats) != 0,
              let totalResetCount = jsonInteger(stats, "total") else {
            return nil
        }

        let latestReset = jsonObject(data, "latest_reset")
        let scheduledResetObject = jsonObject(data, "scheduled_reset")
        let activeWatchObject = jsonObject(data, "active_watch")
        let metadata = jsonMember(root, "meta")

        let lastResetAt = jsonString(stats, "last_reset_at") ??
            jsonString(latestReset, "announced_at")
        let generatedAt = jsonString(metadata, "generated_at")
        let source = jsonMember(latestReset, "source")
        let sourceAuthor = Self.displayAuthor(jsonString(source, "author"))
        let resetChancePercent = jsonInteger(activeWatchObject, "reset_chance_percent")
            .map { min(max($0, 0), 100) }
        let scheduledReset = scheduledResetObject.map {
            CodexResetQuery.ScheduledReset(
                scheduledForText: TiboResetDate.gmt8Display(
                    fromISO8601: jsonString($0, "scheduled_for")
                )
            )
        }
        let activeWatch = activeWatchObject.map {
            CodexResetQuery.ActiveWatch(
                resetChancePercent: resetChancePercent,
                forecastText: Self.nonEmptyText(jsonString($0, "forecast_window"))
            )
        }

        return CodexResetQuery(
            revision: 0,
            serviceState: .ready,
            isStale: false,
            scheduledReset: scheduledReset,
            activeWatch: activeWatch,
            hoursSinceLastReset: TiboResetDate.hours(from: lastResetAt, to: generatedAt),
            totalResetCount: totalResetCount,
            lastHTTPStatus: httpStatus,
            lastResetText: TiboResetDate.gmt8Display(fromISO8601: lastResetAt),
            latestPostText: Self.displayPostText(jsonString(latestReset, "text")),
            sourceAuthor: sourceAuthor
        )
    }

    private func jsonObject(
        _ object: UnsafePointer<cJSON>?,
        _ name: StaticString
    ) -> UnsafeMutablePointer<cJSON>? {
        guard let item = jsonMember(object, name), cJSON_IsObject(item) != 0 else {
            return nil
        }
        return item
    }

    private func jsonMember(
        _ object: UnsafePointer<cJSON>?,
        _ name: StaticString
    ) -> UnsafeMutablePointer<cJSON>? {
        guard let object else { return nil }
        return cJSON_GetObjectItemCaseSensitive(
            object,
            UnsafePointer<CChar>(OpaquePointer(name.utf8Start))
        )
    }

    private func jsonString(
        _ object: UnsafePointer<cJSON>?,
        _ name: StaticString
    ) -> String? {
        guard let item = jsonMember(object, name),
              cJSON_IsString(item) != 0,
              let value = item.pointee.valuestring else {
            return nil
        }
        return String(cString: value)
    }

    private func jsonInteger(
        _ object: UnsafePointer<cJSON>?,
        _ name: StaticString
    ) -> Int? {
        guard let item = jsonMember(object, name), cJSON_IsNumber(item) != 0 else {
            return nil
        }
        return Int(item.pointee.valueint)
    }

    private static func displayAuthor(_ author: String?) -> String? {
        guard let author = nonEmptyText(author) else { return nil }
        return author.utf8.first == 64 ? author : "@" + author
    }

    private static func nonEmptyText(_ text: String?) -> String? {
        guard let text, !text.utf8.isEmpty else { return nil }
        return text
    }

    private static func displayPostText(_ text: String?) -> String? {
        guard let text = nonEmptyText(text) else { return nil }
        let input = Array(text.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(min(input.count, maximumPostByteCount))
        var inputIndex = 0
        var previousWasSpace = false
        var truncated = false
        while inputIndex < input.count {
            if input[inputIndex] == 32,
               inputIndex + 4 < input.count,
               input[inputIndex + 1] == 104,
               input[inputIndex + 2] == 116,
               input[inputIndex + 3] == 116,
               input[inputIndex + 4] == 112 {
                break
            }

            let firstByte = input[inputIndex]
            let characterLength: Int
            if firstByte & 0xE0 == 0xC0 {
                characterLength = 2
            } else if firstByte & 0xF0 == 0xE0 {
                characterLength = 3
            } else if firstByte & 0xF8 == 0xF0 {
                characterLength = 4
            } else {
                characterLength = 1
            }
            guard inputIndex + characterLength <= input.count else { break }

            let isSpace = characterLength == 1 &&
                (firstByte == 9 || firstByte == 10 || firstByte == 13 || firstByte == 32)
            if isSpace && previousWasSpace {
                inputIndex += characterLength
                continue
            }
            if output.count + characterLength > maximumPostByteCount {
                truncated = true
                break
            }
            if isSpace {
                output.append(32)
            } else {
                output.append(contentsOf: input[inputIndex..<(inputIndex + characterLength)])
            }
            previousWasSpace = isSpace
            inputIndex += characterLength
        }
        while output.last == 32 {
            output.removeLast()
        }
        if truncated {
            output.append(contentsOf: [46, 46, 46])
        }
        return String(decoding: output, as: UTF8.self)
    }

    private func publish(_ snapshot: CodexResetQuery) {
        vPortEnterCritical()
        cachedSnapshot = CodexResetQuery(
            revision: cachedSnapshot.revision + 1,
            serviceState: snapshot.serviceState,
            isStale: snapshot.isStale,
            scheduledReset: snapshot.scheduledReset,
            activeWatch: snapshot.activeWatch,
            hoursSinceLastReset: snapshot.hoursSinceLastReset,
            totalResetCount: snapshot.totalResetCount,
            lastHTTPStatus: snapshot.lastHTTPStatus,
            lastResetText: snapshot.lastResetText,
            latestPostText: snapshot.latestPostText,
            sourceAuthor: snapshot.sourceAuthor
        )
        vPortExitCritical()
    }

    private func publishError(httpStatus: Int) {
        vPortEnterCritical()
        let previous = cachedSnapshot
        cachedSnapshot = CodexResetQuery(
            revision: previous.revision + 1,
            serviceState: previous.serviceState == .ready ? .ready : .error,
            isStale: previous.serviceState == .ready,
            scheduledReset: previous.scheduledReset,
            activeWatch: previous.activeWatch,
            hoursSinceLastReset: previous.hoursSinceLastReset,
            totalResetCount: previous.totalResetCount,
            lastHTTPStatus: httpStatus == 0 ? nil : httpStatus,
            lastResetText: previous.lastResetText,
            latestPostText: previous.latestPostText,
            sourceAuthor: previous.sourceAuthor
        )
        vPortExitCritical()
    }
}

@_cdecl("swift_tibo_reset_monitor_task")
private func swiftTiboResetMonitorTask(_ context: UnsafeMutableRawPointer?) {
    _ = context
    TiboResetMonitor.shared.runWorker()
}

@_cdecl("swift_tibo_http_event_handler")
private func swiftTiboHTTPEventHandler(
    _ event: UnsafeMutablePointer<esp_http_client_event_t>?
) -> esp_err_t {
    guard let event,
          event.pointee.event_id == HTTP_EVENT_ON_DATA,
          event.pointee.data_len > 0,
          let userData = event.pointee.user_data,
          let eventData = event.pointee.data else {
        return ESP_OK
    }

    let response = userData.assumingMemoryBound(to: TiboHTTPResponseBuffer.self)
    let incomingLength = Int(event.pointee.data_len)
    guard response.pointee.length + incomingLength < response.pointee.capacity else {
        response.pointee.overflowed = true
        return ESP_FAIL
    }
    let destination = response.pointee.bytes.advanced(by: response.pointee.length)
    destination.update(
        from: eventData.assumingMemoryBound(to: CChar.self),
        count: incomingLength
    )
    response.pointee.length += incomingLength
    response.pointee.bytes[response.pointee.length] = 0
    return ESP_OK
}
