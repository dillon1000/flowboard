import Fluent
import Vapor

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.get("config", use: configuration)
        auth.post("register", use: register)
        auth.post("login", use: login)

        let protected = auth.grouped(User.guardMiddleware())
        protected.get("me", use: me)
        protected.patch("me", use: updateProfile)
        protected.post("logout", use: logout)
        try protected.register(collection: APIKeyController())
        try protected.register(collection: CalendarFeedManagementController())
    }

    func configuration(req: Request) -> AuthConfigurationResponse {
        AuthConfigurationResponse(
            oauthEnabled: req.application.oauthConfiguration != nil,
            oauthProviderName: req.application.oauthConfiguration?.providerName ?? "OAuth"
        )
    }

    func register(req: Request) async throws -> Response {
        try RegisterRequest.validate(content: req)
        let input = try req.content.decode(RegisterRequest.self)
        let user = try await AuthService.register(input, on: req.db)
        req.auth.login(user)
        if let configuration = req.application.notificationConfiguration {
            await NotificationService.enqueue(
                try NotificationEvent.welcome(
                    user: user,
                    appURL: configuration.appURL(path: "/app")
                ),
                for: req
            )
        }
        return try await UserResponse(user: user).encodeResponse(status: .created, for: req)
    }

    func login(req: Request) async throws -> UserResponse {
        try LoginRequest.validate(content: req)
        let input = try req.content.decode(LoginRequest.self)
        let user = try await AuthService.authenticate(input, on: req.db)
        req.auth.login(user)
        return try UserResponse(user: user)
    }

    func me(req: Request) throws -> UserResponse {
        try UserResponse(user: req.auth.require(User.self))
    }

    func updateProfile(req: Request) async throws -> UserResponse {
        try UpdateProfileRequest.validate(content: req)
        let input = try req.content.decode(UpdateProfileRequest.self)
        let user = try req.auth.require(User.self)
        user.name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timeZoneIdentifier = try validatedTimeZoneIdentifier(input.timeZone) {
            user.timeZoneIdentifier = timeZoneIdentifier
        }
        if let dailyBriefEnabled = input.dailyBriefEnabled {
            user.dailyBriefEnabled = dailyBriefEnabled
        }
        if let weeklyPlanningPromptEnabled = input.weeklyPlanningPromptEnabled {
            user.weeklyPlanningPromptEnabled = weeklyPlanningPromptEnabled
        }
        if let planningEmailHour = input.planningEmailHour {
            guard (0...23).contains(planningEmailHour) else {
                throw Abort(.unprocessableEntity, reason: "Choose a delivery hour from 0 to 23.")
            }
            user.planningEmailHour = planningEmailHour
        }
        try await user.update(on: req.db)
        return try UserResponse(user: user)
    }

    func logout(req: Request) -> HTTPStatus {
        req.auth.logout(User.self)
        req.session.destroy()
        return .noContent
    }
}

struct AuthConfigurationResponse: Content {
    let oauthEnabled: Bool
    let oauthProviderName: String
}
