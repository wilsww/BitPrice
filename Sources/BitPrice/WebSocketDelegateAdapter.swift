import Foundation

@MainActor
final class WebSocketDelegateAdapter: NSObject, URLSessionWebSocketDelegate, WebSocketDelegateReceiving {
    private weak var controller: BinanceFeedController?
    private var connectionByTaskIdentifier: [Int: UUID] = [:]

    func attach(controller: BinanceFeedController) {
        self.controller = controller
    }

    func register(taskIdentifier: Int, connectionID: UUID) {
        connectionByTaskIdentifier[taskIdentifier] = connectionID
    }

    func unregister(taskIdentifier: Int, connectionID: UUID) {
        guard connectionByTaskIdentifier[taskIdentifier] == connectionID else { return }
        connectionByTaskIdentifier.removeValue(forKey: taskIdentifier)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let taskIdentifier = webSocketTask.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self, let connectionID = self.connectionByTaskIdentifier[taskIdentifier] else { return }
            self.controller?.didOpen(taskIdentifier: taskIdentifier, connectionID: connectionID)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let taskIdentifier = webSocketTask.taskIdentifier
        let failure = NetworkFailure(
            domain: "websocket-close",
            code: Int(closeCode.rawValue),
            message: "Binance WebSocket closed (\(closeCode.rawValue))"
        )
        Task { @MainActor [weak self] in
            guard let self, let connectionID = self.connectionByTaskIdentifier[taskIdentifier] else { return }
            self.controller?.didClose(taskIdentifier: taskIdentifier, connectionID: connectionID, failure: failure)
        }
    }
}

@MainActor
final class SystemWebSocketTaskTransport: WebSocketTaskTransport {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    var taskIdentifier: Int { task.taskIdentifier }

    var maximumMessageSize: Int {
        get { task.maximumMessageSize }
        set { task.maximumMessageSize = newValue }
    }

    func resume() { task.resume() }

    func receive() async throws -> WebSocketInboundMessage {
        do {
            switch try await task.receive() {
            case .string(let value): return .string(value)
            case .data(let value): return .data(value)
            @unknown default:
                throw NetworkFailure(domain: "websocket", code: -2, message: "Unknown WebSocket message type")
            }
        } catch {
            throw NetworkFailure.wrapping(error, domain: "websocket")
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

@MainActor
final class SystemWebSocketSessionTransport: WebSocketSessionTransport {
    private let session: URLSession

    init(delegate: WebSocketDelegateAdapter) {
        session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: .main)
    }

    func makeTask(url: URL) -> any WebSocketTaskTransport {
        SystemWebSocketTaskTransport(task: session.webSocketTask(with: url))
    }

    func invalidate() {
        session.invalidateAndCancel()
    }
}

@MainActor
final class SystemWebSocketSessionFactory: WebSocketSessionFactory {
    func makeLifetimeSession(delegate: any WebSocketDelegateReceiving) -> any WebSocketSessionTransport {
        guard let adapter = delegate as? WebSocketDelegateAdapter else {
            preconditionFailure("System WebSocket sessions require WebSocketDelegateAdapter")
        }
        return SystemWebSocketSessionTransport(delegate: adapter)
    }
}
