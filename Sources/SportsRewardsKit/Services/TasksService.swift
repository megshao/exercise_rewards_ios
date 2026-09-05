import Foundation

/// 「我的任務」服務：取任務清單、組截圖圖片 URL。
public final class TasksService: TasksServicing {
    private let http: HTTPClienting
    private let log = SecureLog(.tasks)

    public init(http: HTTPClienting) {
        self.http = http
    }

    public func fetchTasks() async throws -> [TaskPeriod] {
        let html = try await http.getHTML(path: "/member/tasks")
        let tasks = try TaskParser.parse(html: html)
        log.debug("fetched \(tasks.count) task periods")
        return tasks
    }

    public func screenshotURL(taskID: String) async throws -> URL {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        guard let url = URL(string: SiteConfig.base + "/member/screenshot/" + taskID) else {
            throw AppError.parsing("invalid screenshot URL")
        }
        return url
    }

    public func screenshotImageURL(taskID: String) async throws -> URL {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        guard let location = try await http.redirectLocation(path: "/member/screenshot/" + taskID) else {
            log.error("screenshot endpoint did not redirect")
            throw AppError.unexpectedResponse(0)
        }
        guard let url = URL(string: location) else {
            throw AppError.parsing("invalid screenshot redirect location")
        }
        log.debug("resolved screenshot redirect location")
        return url
    }
}
