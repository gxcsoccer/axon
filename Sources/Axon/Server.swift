import AxonCore
import Foundation
import Hummingbird

/// Build the Hummingbird HTTP server with all API routes.
func buildServer(controller: AxonController, hostname: String, port: Int, authToken: String?) -> some ApplicationProtocol {
    let router = Router()

    // Auth middleware on router level (skips /health inside the middleware)
    if let token = authToken {
        router.add(middleware: AuthMiddleware(token: token))
    }

    // Health check (middleware skips this path)
    router.get("/health") { _, _ in
        return Response(status: .ok, body: .init(byteBuffer: .init(string: "{\"status\":\"ok\"}")))
    }

    // POST /action — unified action endpoint
    router.post("/action") { request, context in
        let body = try await request.body.collect(upTo: 1_048_576) // 1MB max
        let decoder = JSONDecoder()
        let action = try decoder.decode(ComputerAction.self, from: body)
        let result = await controller.execute(action)
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        return Response(
            status: result.success ? .ok : .unprocessableContent,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    // Convenience endpoints

    // GET /apps — list running apps
    router.get("/apps") { _, _ in
        let result = await controller.execute(.listApps)
        return try jsonResponse(result)
    }

    // POST /launch — launch an app
    router.post("/launch") { request, context in
        let body = try await decodeBody(request, as: LaunchRequest.self)
        let result = await controller.execute(.launchApp(bundleId: body.bundleId))
        return try jsonResponse(result)
    }

    // POST /quit — quit an app
    router.post("/quit") { request, context in
        let body = try await decodeBody(request, as: QuitRequest.self)
        let result = await controller.execute(.quitApp(bundleId: body.bundleId))
        return try jsonResponse(result)
    }

    // POST /ui-tree — get UI tree
    router.post("/ui-tree") { request, context in
        let body = try await decodeBody(request, as: UITreeRequest.self)
        let result = await controller.execute(.getUITree(bundleId: body.bundleId, maxDepth: body.maxDepth))
        return try jsonResponse(result)
    }

    // POST /find — find a UI element
    router.post("/find") { request, context in
        let body = try await decodeBody(request, as: FindRequest.self)
        let result = await controller.execute(.findElement(bundleId: body.bundleId, query: body.query))
        return try jsonResponse(result)
    }

    // POST /wait — wait for an element to appear
    router.post("/wait") { request, context in
        let body = try await decodeBody(request, as: WaitRequest.self)
        let result = await controller.execute(.waitForElement(bundleId: body.bundleId, query: body.query, timeout: body.timeout))
        return try jsonResponse(result)
    }

    // POST /click — click a UI element by query
    router.post("/click") { request, context in
        let body = try await decodeBody(request, as: ClickRequest.self)
        if let query = body.query, let bundleId = body.bundleId {
            let result = await controller.execute(.clickElement(bundleId: bundleId, query: query))
            return try jsonResponse(result)
        } else if let x = body.x, let y = body.y {
            let result = await controller.execute(.clickAt(x: x, y: y))
            return try jsonResponse(result)
        } else {
            return try jsonResponse(.fail("Provide either (bundleId + query) or (x + y)"))
        }
    }

    // POST /type — type text (into element or raw)
    router.post("/type") { request, context in
        let body = try await decodeBody(request, as: TypeRequest.self)
        if let bundleId = body.bundleId, let query = body.query {
            let result = await controller.execute(.typeIntoElement(bundleId: bundleId, query: query, text: body.text))
            return try jsonResponse(result)
        } else {
            let result = await controller.execute(.typeText(text: body.text))
            return try jsonResponse(result)
        }
    }

    // POST /key — press a key combo
    router.post("/key") { request, context in
        let body = try await decodeBody(request, as: KeyRequest.self)
        let result = await controller.execute(.pressKey(key: body.key, modifiers: body.modifiers))
        return try jsonResponse(result)
    }

    // POST /screenshot — capture screen, window, or region
    router.post("/screenshot") { request, context in
        let body = try? await decodeBody(request, as: ScreenshotRequest.self)
        let result: ActionResult
        if let region = body?.region {
            result = await controller.execute(.regionScreenshot(x: region.x, y: region.y, width: region.width, height: region.height, displayId: body?.displayId))
        } else if let bundleId = body?.bundleId {
            result = await controller.execute(.windowScreenshot(bundleId: bundleId, title: body?.windowTitle))
        } else {
            result = await controller.execute(.screenshot(displayId: body?.displayId))
        }
        return try jsonResponse(result)
    }

    // Also allow GET for convenience
    router.get("/screenshot") { _, _ in
        let result = await controller.execute(.screenshot(displayId: nil))
        return try jsonResponse(result)
    }

    // POST /text — get text content of an element
    router.post("/text") { request, context in
        let body = try await decodeBody(request, as: FindRequest.self)
        let result = await controller.execute(.getElementText(bundleId: body.bundleId, query: body.query))
        return try jsonResponse(result)
    }

    // POST /perform-action — perform a named AX action on an element
    router.post("/perform-action") { request, context in
        let body = try await decodeBody(request, as: PerformActionRequest.self)
        let result = await controller.execute(.performAction(bundleId: body.bundleId, query: body.query, action: body.action))
        return try jsonResponse(result)
    }

    // POST /script — run AppleScript or JXA
    router.post("/script") { request, context in
        let body = try await decodeBody(request, as: ScriptRequest.self)
        let result: ActionResult
        if body.language == "jxa" || body.language == "javascript" {
            result = await controller.execute(.runJXA(script: body.script))
        } else {
            result = await controller.execute(.runAppleScript(script: body.script))
        }
        return try jsonResponse(result)
    }

    // POST /drag — drag from one point to another
    router.post("/drag") { request, context in
        let body = try await decodeBody(request, as: DragRequest.self)
        let result = await controller.execute(.drag(fromX: body.fromX, fromY: body.fromY, toX: body.toX, toY: body.toY))
        return try jsonResponse(result)
    }

    // GET /cursor-position — get current cursor position
    router.get("/cursor-position") { _, _ in
        let result = await controller.execute(.getCursorPosition)
        return try jsonResponse(result)
    }

    // GET /screen-info — get screen information
    router.get("/screen-info") { _, _ in
        let result = await controller.execute(.getScreenInfo)
        return try jsonResponse(result)
    }

    // POST /region-screenshot — capture a region of the screen
    router.post("/region-screenshot") { request, context in
        let body = try await decodeBody(request, as: RegionScreenshotRequest.self)
        let result = await controller.execute(.regionScreenshot(x: body.x, y: body.y, width: body.width, height: body.height, displayId: body.displayId))
        return try jsonResponse(result)
    }

    // GET /clipboard — read clipboard contents
    router.get("/clipboard") { _, _ in
        let result = await controller.execute(.clipboardRead)
        return try jsonResponse(result)
    }

    // POST /clipboard — set clipboard contents
    router.post("/clipboard") { request, context in
        let body = try await decodeBody(request, as: ClipboardRequest.self)
        let result = await controller.execute(.clipboardWrite(text: body.text))
        return try jsonResponse(result)
    }

    // GET /active-window — get active window info
    router.get("/active-window") { _, _ in
        let result = await controller.execute(.getActiveWindow)
        return try jsonResponse(result)
    }

    // POST /move-window — move a window
    router.post("/move-window") { request, context in
        let body = try await decodeBody(request, as: MoveWindowRequest.self)
        let result = await controller.execute(.moveWindow(bundleId: body.bundleId, x: body.x, y: body.y))
        return try jsonResponse(result)
    }

    // POST /resize-window — resize a window
    router.post("/resize-window") { request, context in
        let body = try await decodeBody(request, as: ResizeWindowRequest.self)
        let result = await controller.execute(.resizeWindow(bundleId: body.bundleId, width: body.width, height: body.height))
        return try jsonResponse(result)
    }

    // GET /audit — get recent audit log
    router.get("/audit") { _, _ in
        let entries = await controller.security.getRecentAuditLog()
        let data = try JSONEncoder().encode(entries)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    // GET /config — get security config
    router.get("/config") { _, _ in
        let config = await controller.security.getConfig()
        let data = try JSONEncoder().encode(config)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    let app = Application(router: router, configuration: .init(address: .hostname(hostname, port: port)))
    return app
}

// MARK: - Auth Middleware

struct AuthMiddleware: RouterMiddleware {
    let token: String

    func handle(_ request: Request, context: BasicRequestContext, next: (Request, BasicRequestContext) async throws -> Response) async throws -> Response {
        // Skip auth for health check
        if request.uri.path == "/health" {
            return try await next(request, context)
        }
        guard let authHeader = request.headers[.authorization],
              authHeader == "Bearer \(token)" else {
            return Response(
                status: .unauthorized,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{\"error\":\"Unauthorized\"}"))
            )
        }
        return try await next(request, context)
    }
}

// MARK: - Request Types

struct LaunchRequest: Codable { var bundleId: String }
struct QuitRequest: Codable { var bundleId: String }
struct UITreeRequest: Codable { var bundleId: String; var maxDepth: Int? }
struct FindRequest: Codable { var bundleId: String; var query: ElementQuery }
struct WaitRequest: Codable { var bundleId: String; var query: ElementQuery; var timeout: Double? }
struct ClickRequest: Codable { var bundleId: String?; var query: ElementQuery?; var x: Double?; var y: Double? }
struct TypeRequest: Codable { var bundleId: String?; var query: ElementQuery?; var text: String }
struct KeyRequest: Codable { var key: String; var modifiers: [String]? }
struct ScreenshotRequest: Codable {
    var displayId: Int?
    var bundleId: String?
    var windowTitle: String?
    var region: RegionRect?
}
struct RegionRect: Codable { var x: Int; var y: Int; var width: Int; var height: Int }
struct ScriptRequest: Codable { var script: String; var language: String? }
struct PerformActionRequest: Codable { var bundleId: String; var query: ElementQuery; var action: String }
struct DragRequest: Codable { var fromX: Double; var fromY: Double; var toX: Double; var toY: Double }
struct RegionScreenshotRequest: Codable { var x: Int; var y: Int; var width: Int; var height: Int; var displayId: Int? }
struct ClipboardRequest: Codable { var text: String }
struct MoveWindowRequest: Codable { var bundleId: String; var x: Double; var y: Double }
struct ResizeWindowRequest: Codable { var bundleId: String; var width: Double; var height: Double }

// MARK: - Helpers

private func decodeBody<T: Decodable>(_ request: Request, as type: T.Type) async throws -> T {
    let body = try await request.body.collect(upTo: 1_048_576)
    return try JSONDecoder().decode(type, from: body)
}

private func jsonResponse(_ result: ActionResult) throws -> Response {
    let data = try JSONEncoder().encode(result)
    return Response(
        status: result.success ? .ok : .unprocessableContent,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: .init(data: data))
    )
}
