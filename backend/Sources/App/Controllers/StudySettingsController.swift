import Fluent
import Foundation
import Vapor

/// Manages the planning inputs that belong to the signed-in student. Task
/// estimates still pass through board access checks before any row changes.
struct StudySettingsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let settings = routes.grouped("study-settings")
        settings.get(use: get)
        settings.put(use: update)
        settings.post("estimates", use: bulkEstimate)
    }

    func get(req: Request) async throws -> StudySettingsResponse {
        let userID = try req.auth.require(User.self).requireID()
        return StudySettingsResponse(settings: try await find(userID: userID, on: req.db))
    }

    func update(req: Request) async throws -> StudySettingsResponse {
        let input = try req.content.decode(StudySettingsRequest.self)
        try validate(input)
        let userID = try req.auth.require(User.self).requireID()
        let settings = try await find(userID: userID, on: req.db)
            ?? StudySettings(userID: userID)
        settings.weekdayCapacityMinutes = input.weekdayCapacityMinutes
        settings.blockedDates = Array(Set(input.blockedDates)).sorted()
        settings.recurringCommitments = input.recurringCommitments
        settings.calendarConflicts = input.calendarConflicts
        settings.estimatePresets = input.estimatePresets
        settings.timeZoneConfirmed = input.timeZoneConfirmed
        settings.availabilityConfigured = input.availabilityConfigured
        try await settings.save(on: req.db)
        return StudySettingsResponse(settings: settings)
    }

    /// Updates many estimates in one transaction and optionally replaces the
    /// reusable presets. Any inaccessible task rejects the full request.
    func bulkEstimate(req: Request) async throws -> BulkTaskEstimatesResponse {
        let input = try req.content.decode(BulkTaskEstimatesRequest.self)
        guard !input.estimates.isEmpty, input.estimates.count <= 200 else {
            throw Abort(.unprocessableEntity, reason: "Estimate between 1 and 200 assignments at a time.")
        }
        guard Set(input.estimates.map(\.taskID)).count == input.estimates.count else {
            throw Abort(.unprocessableEntity, reason: "Each assignment can appear only once.")
        }
        guard input.estimates.allSatisfy({ (5...1_440).contains($0.estimatedMinutes) }) else {
            throw Abort(.unprocessableEntity, reason: "Each estimate must be between 5 and 1440 minutes.")
        }
        if let presets = input.estimatePresets {
            try validate(presets: presets)
        }

        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        let taskIDs = input.estimates.map(\.taskID)
        let tasks = try await Task.query(on: req.db)
            .filter(\.$id ~~ taskIDs)
            .filter(\.$board.$id ~~ boardIDs)
            .all()
        guard tasks.count == taskIDs.count else {
            throw Abort(.notFound, reason: "One or more assignments do not exist.")
        }
        let minutesByTaskID = Dictionary(
            uniqueKeysWithValues: input.estimates.map { ($0.taskID, $0.estimatedMinutes) }
        )

        let savedPresets = try await req.db.transaction { database in
            for task in tasks {
                task.estimatedMinutes = minutesByTaskID[try task.requireID()]
                try await task.update(on: database)
            }
            guard let presets = input.estimatePresets else {
                return (try await self.find(userID: userID, on: database))?.estimatePresets
                    ?? StudyEstimatePreset.defaults
            }
            let settings = try await self.find(userID: userID, on: database)
                ?? StudySettings(userID: userID)
            settings.estimatePresets = presets
            try await settings.save(on: database)
            return presets
        }
        return BulkTaskEstimatesResponse(
            updatedTaskCount: tasks.count,
            estimatePresets: savedPresets
        )
    }

    private func find(userID: UUID, on database: any Database) async throws -> StudySettings? {
        try await StudySettings.query(on: database)
            .filter(\.$user.$id == userID)
            .first()
    }

    private func validate(_ input: StudySettingsRequest) throws {
        let weekdays = Set(StudySettings.defaultWeekdayCapacityMinutes.keys)
        guard Set(input.weekdayCapacityMinutes.keys) == weekdays,
              input.weekdayCapacityMinutes.values.allSatisfy({ (0...1_440).contains($0) }) else {
            throw Abort(.unprocessableEntity, reason: "Set a capacity from 0 to 1440 minutes for every weekday.")
        }
        guard input.blockedDates.count <= 120,
              input.blockedDates.allSatisfy(validDate) else {
            throw Abort(.unprocessableEntity, reason: "Choose valid blocked dates.")
        }
        guard input.recurringCommitments.count <= 100,
              input.recurringCommitments.allSatisfy(validCommitment) else {
            throw Abort(.unprocessableEntity, reason: "Check the class and work shift times.")
        }
        guard input.calendarConflicts.count <= 200,
              input.calendarConflicts.allSatisfy(validConflict) else {
            throw Abort(.unprocessableEntity, reason: "Check the calendar conflict dates and times.")
        }
        try validate(presets: input.estimatePresets)
    }

    private func validate(presets: [StudyEstimatePreset]) throws {
        guard presets.count <= 40,
              Set(presets.map(\.id)).count == presets.count,
              presets.allSatisfy({ preset in
                  !preset.id.isEmpty
                      && (1...40).contains(preset.name.count)
                      && (5...1_440).contains(preset.minutes)
                      && preset.keywords.count <= 12
                      && preset.keywords.allSatisfy { (1...40).contains($0.count) }
              }) else {
            throw Abort(.unprocessableEntity, reason: "Check the reusable estimate defaults.")
        }
    }

    private func validCommitment(_ value: StudyRecurringCommitment) -> Bool {
        !value.id.isEmpty
            && (1...80).contains(value.title.count)
            && ["class", "work"].contains(value.kind)
            && !value.weekdays.isEmpty
            && value.weekdays.allSatisfy { (1...7).contains($0) }
            && validTimeRange(start: value.startTime, end: value.endTime)
    }

    private func validConflict(_ value: StudyCalendarConflict) -> Bool {
        !value.id.isEmpty
            && (1...80).contains(value.title.count)
            && validDate(value.date)
            && validTimeRange(start: value.startTime, end: value.endTime)
    }

    private func validDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = planningDate(value, calendar: calendar) else { return false }
        return planningDateKey(date, calendar: calendar) == value
    }

    private func validTimeRange(start: String, end: String) -> Bool {
        guard let startMinutes = clockMinutes(start), let endMinutes = clockMinutes(end) else {
            return false
        }
        return endMinutes > startMinutes
    }

    private func clockMinutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }
}
