import App
import Vapor

@main
enum Entrypoint {
    static func main() throws {
        var environment = try Environment.detect()
        try LoggingSystem.bootstrap(from: &environment)

        let application = Application(environment)
        defer { application.shutdown() }

        try configure(application)
        try application.run()
    }
}
