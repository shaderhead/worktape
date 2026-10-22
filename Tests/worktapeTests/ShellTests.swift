import Foundation
import Testing
@testable import worktape

struct AsciinemaConfigTests {
    @Test(arguments: [
        ("[notifications]\nenabled = false", true),
        ("[session]\nidle_time_limit = 2\n\n  [notifications]", true),
        ("notifications.command = 'say hi'", true),
        ("[ notifications ]\nenabled = false", true),
        ("[\"notifications\"]\nenabled = false", true),
        ("notifications = { enabled = false }", true),
        ("[notifications_extra]", false),
        ("[session]\nidle_time_limit = 2", false),
        ("# [notifications]", false),
        ("", false),
    ])
    func noticesWhenTheUserConfiguresNotifications(config: String, expected: Bool) {
        #expect(AsciinemaConfig.configuresNotifications(config) == expected)
    }

    @Test func keepsTheUsersSettings() throws {
        try withTemporaryDirectory { directory in
            let userConfig = directory + "/config.toml"
            try "[session]\nidle_time_limit = 2\n".write(toFile: userConfig, atomically: true, encoding: .utf8)
            let config = try #require(try AsciinemaConfig.create(extending: userConfig))
            defer { config.remove() }
            let contents = try String(contentsOfFile: config.directory + "/config.toml", encoding: .utf8)
            #expect(contents.hasPrefix("[session]\nidle_time_limit = 2\n"))
            #expect(contents.contains("[notifications]"))
        }
    }

    @Test func leavesTheUsersNotificationsAlone() throws {
        try withTemporaryDirectory { directory in
            let userConfig = directory + "/config.toml"
            try "[notifications]\nenabled = false\n".write(toFile: userConfig, atomically: true, encoding: .utf8)
            let config = try AsciinemaConfig.create(extending: userConfig)
            #expect(config == nil)
        }
    }

    @Test func notificationsTrackPausing() throws {
        let config = try #require(try AsciinemaConfig.create(extending: "/nonexistent/config.toml"))
        defer { config.remove() }
        #expect(!config.isPaused)
        _ = try run("/bin/sh", ["-c", config.notificationCommand], environment: ["TEXT": "Paused recording"])
        #expect(config.isPaused)
        _ = try run("/bin/sh", ["-c", config.notificationCommand], environment: ["TEXT": "Resumed recording"])
        #expect(!config.isPaused)
    }

    @Test func failsWhenItCannotWriteItsFolder() throws {
        try withTemporaryDirectory { parent in
            chmod(parent, 0o555)
            defer { chmod(parent, 0o755) }
            #expect(throws: (any Error).self) {
                try AsciinemaConfig.create(extending: "/nonexistent/config.toml", in: parent)
            }
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: parent)
            #expect(leftovers.isEmpty)
        }
    }

    @Test func removesItsFolder() throws {
        let config = try #require(try AsciinemaConfig.create(extending: "/nonexistent/config.toml"))
        config.remove()
        #expect(!FileManager.default.fileExists(atPath: config.directory))
    }
}

struct HookTests {
    func zsh(_ script: String, environment: [String: String] = [:]) throws -> Output {
        try withTemporaryDirectory { directory in
            let hook = directory + "/hook.zsh"
            try zshHook.write(toFile: hook, atomically: true, encoding: .utf8)
            let path = directory + "/test.zsh"
            try "source \(hook)\n\(script)\n".write(toFile: path, atomically: true, encoding: .utf8)
            return try run("/bin/zsh", ["-f", path], environment: environment)
        }
    }

    @Test func remindsYouOnceWhenYouEnterAProject() throws {
        try withTemporaryDirectory { root in
            #expect(initialise(root) == 0)
            try FileManager.default.createDirectory(atPath: root + "/src", withIntermediateDirectories: false)
            let output = try zsh("cd \(root); cd src; cd /; cd \(root)")
            #expect(output.standardError.components(separatedBy: "worktape not recording").count - 1 == 2)
        }
    }

    @Test func staysQuietWhileRecording() throws {
        try withTemporaryDirectory { root in
            #expect(initialise(root) == 0)
            let output = try zsh("cd \(root)", environment: ["WORKTAPE_RECORDING": root])
            #expect(output.standardError.isEmpty)
        }
    }

    @Test func marksThePromptWhileRecordingAndPaused() throws {
        try withTemporaryDirectory { state in
            let script = """
            PROMPT='> '
            _worktape_prompt; _worktape_prompt
            print -r -- "$PROMPT|${psvar[8]}|${psvar[9]}"
            : > \(state)/paused
            _worktape_prompt
            print -r -- "${psvar[8]}|${psvar[9]}"
            """
            let output = try zsh(script, environment: ["WORKTAPE_RECORDING": "/project", "WORKTAPE_STATE": state])
            let lines = output.standardOutput.split(separator: "\n")
            #expect(lines.first == "> %(8V.%F{red}●%f .)%(9V.%F{yellow}‖%f .)|1|")
            #expect(lines.last == "|1")
            #expect(FileManager.default.fileExists(atPath: state + "/prompt"))
        }
    }

    @Test func leavesThePromptAloneOutsideARecording() throws {
        let output = try zsh("PROMPT='> '; print -r -- \"$PROMPT\"; whence _worktape_prompt || print none")
        #expect(output.standardOutput == "> \nnone\n")
    }
}
