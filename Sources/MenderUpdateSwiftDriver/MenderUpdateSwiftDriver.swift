//
// Copyright (c) 2025-2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import AsyncAlgorithms
import Foundation
import Logging
import Subprocess
#if canImport(System)
import System
#elseif canImport(SystemPackage)
import SystemPackage
#endif

private extension Logger.Level {
  var _menderLogLevel: String {
    switch self {
    case .trace:
      "trace"
    case .debug:
      "debug"
    case .info:
      "info"
    case .notice:
      "info"
    case .warning:
      "warning"
    case .error:
      "error"
    case .critical:
      "fatal"
    }
  }

  init?(_menderLogLevel: String) {
    switch _menderLogLevel {
    case "trace":
      self = .trace
    case "debug":
      self = .debug
    case "info":
      self = .info
    case "warning":
      self = .warning
    case "error":
      self = .error
    case "fatal":
      self = .critical
    default:
      return nil
    }
  }
}

public struct MenderUpdateError: Error, Sendable {
  public enum Code: Subprocess.TerminationStatus.Code, Sendable {
    case couldNotFulfillRequest = 1
    case noUpdateInProgress = 2
    case reboot = 4
  }

  public struct LogMessage: Sendable {
    public let recordID: UInt
    public let severity: Logger.Level
    public let time: Date
    public let name: String
    public let message: String

    fileprivate func _log(with logger: Logger) {
      logger.log(
        level: severity,
        "\(message)",
        metadata: [
          "MENDER_RECORD_ID": "\(recordID)",
          "MENDER_TIMESTAMP": "\(time)",
          "MENDER_NAME": "\(name)",
        ]
      )
    }

    private init(
      recordID: UInt,
      severity: Logger.Level,
      time: Date,
      name: String,
      message: String
    ) {
      self.recordID = recordID
      self.severity = severity
      self.time = time
      self.name = name
      self.message = message
    }

    private static func _parseKeyValuePairs(from line: String) -> [String: String] {
      var result = [String: String]()
      var remaining = line[...]

      while !remaining.isEmpty {
        guard let equalsIndex = remaining.firstIndex(of: "=") else { break }
        let key = String(remaining[..<equalsIndex])
        remaining = remaining[remaining.index(after: equalsIndex)...]

        let value: String
        if remaining.first == "\"" {
          remaining = remaining.dropFirst()
          guard let endQuoteIndex = remaining.firstIndex(of: "\"") else { break }
          value = String(remaining[..<endQuoteIndex])
          remaining = remaining[remaining.index(after: endQuoteIndex)...]
          if remaining.first == " " {
            remaining = remaining.dropFirst()
          }
        } else {
          if let spaceIndex = remaining.firstIndex(of: " ") {
            value = String(remaining[..<spaceIndex])
            remaining = remaining[remaining.index(after: spaceIndex)...]
          } else {
            value = String(remaining)
            remaining = ""
          }
        }

        result[key] = value
      }

      return result
    }

    fileprivate init?(parsing line: String) {
      let pairs = Self._parseKeyValuePairs(from: line)

      guard let recordIDString = pairs["record_id"],
            let recordID = UInt(recordIDString),
            let severityString = pairs["severity"],
            let severity = Logger.Level(_menderLogLevel: severityString),
            let timeString = pairs["time"],
            let name = pairs["name"],
            let message = pairs["msg"]
      else {
        return nil
      }

      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MMM-dd HH:mm:ss.SSSSSS"
      formatter.locale = Locale(identifier: "en_US_POSIX")
      guard let time = formatter.date(from: timeString) else {
        return nil
      }

      self.init(recordID: recordID, severity: severity, time: time, name: name, message: message)
    }
  }

  public let code: Code
  public let message: String?
  public let logMessages: [LogMessage]

  fileprivate init(code: Code, message: String? = nil, logMessages: [LogMessage] = []) {
    self.code = code
    self.message = message
    self.logMessages = logMessages
  }

  fileprivate init?(
    rawValue code: Subprocess.TerminationStatus.Code,
    message: String? = nil,
    logMessages: [LogMessage] = []
  ) {
    guard let code = Code(rawValue: code) else {
      return nil
    }
    self.init(code: code, message: message, logMessages: logMessages)
  }

  fileprivate static let couldNotFulfillRequest = Self(code: .couldNotFulfillRequest)
  fileprivate static let noUpdateInProgress = Self(code: .noUpdateInProgress)
  fileprivate static let reboot = Self(code: .reboot)

  public func log(with logger: Logger) {
    logMessages.forEach { $0._log(with: logger) }
  }
}

public struct MenderUpdateSwiftDriver: Sendable {
  public enum State: Equatable, Sendable {
    case ArtifactInstall_Enter
    case ArtifactCommit_Enter
    case ArtifactCommit_Leave
    case ArtifactRollback_Enter
    case ArtifactFailure_Enter
    case Cleanup
  }

  public enum Command: Equatable, Sendable {
    case install(URL)
    case commit
    case resume
    case rollback

    fileprivate var _menderUpdateCommand: String {
      switch self {
      case .install:
        "install"
      case .commit:
        "commit"
      case .resume:
        "resume"
      case .rollback:
        "rollback"
      }
    }
  }

  public struct Options: Sendable {
    public let config: String?
    public let fallbackConfig: String?
    public let dataStore: String?
    public let logLevel: Logger.Level
    public let trustedCerts: String?
    public let skipVerify: Bool

    public init(
      config: String? = nil,
      fallbackConfig: String? = nil,
      dataStore: String? = nil,
      logLevel: Logger.Level = .info,
      trustedCerts: String? = nil,
      skipVerify: Bool = false
    ) {
      self.config = config
      self.fallbackConfig = fallbackConfig
      self.dataStore = dataStore
      self.logLevel = logLevel
      self.trustedCerts = trustedCerts
      self.skipVerify = skipVerify
    }

    fileprivate var _menderUpdateArguments: [String] {
      var arguments = [String]()

      if let config { arguments += ["--config", config] }
      if let fallbackConfig { arguments += ["--fallback-config", fallbackConfig] }
      if let dataStore { arguments += ["--datastore", dataStore] }
      arguments += ["--log-level", logLevel._menderLogLevel]
      if let trustedCerts { arguments += ["--trusted-certs", trustedCerts] }
      if skipVerify { arguments += ["--skipverify"] }

      return arguments
    }
  }

  private let _binaryPath: FilePath
  private let _options: Options

  private func _menderUpdateArgumentsArray(
    command: Command,
    stoppingBefore state: State? = nil
  ) -> [String] {
    // mender-update [global options] command [command options] [arguments...]

    var arguments: [String] = _options._menderUpdateArguments + [command._menderUpdateCommand]

    if case .install = command {
      arguments += ["--reboot-exit-code"]
    } else if command == .resume {
      arguments += ["--reboot-exit-code"]
    }

    if let state {
      arguments += ["--stop-before", String(describing: state)]
    }

    if case let .install(artifact) = command {
      arguments += [artifact.absoluteString]
    }

    return arguments
  }

  private func _menderUpdateArguments(
    command: Command,
    stoppingBefore state: State? = nil
  ) -> Subprocess.Arguments {
    .init(_menderUpdateArgumentsArray(command: command, stoppingBefore: state))
  }

  public init(options: Options = .init(), binaryPath: FilePath = "/usr/bin/mender-update") {
    _options = options
    _binaryPath = binaryPath
  }

  package func execute(
    command: Command,
    stoppingBefore state: State? = nil,
    progressCallback: (@Sendable (Int) -> ())? = nil
  ) async throws {
    let arguments = _menderUpdateArguments(command: command, stoppingBefore: state)

    let process = try await Subprocess.run(
      .path(_binaryPath),
      arguments: arguments,
      // Use a small buffer size (3 bytes minimum for "\rD%") to enable
      // real-time progress updates by forcing frequent pipe reads
      preferredBufferSize: progressCallback != nil ? 3 : nil
    ) { _, _, output, error in
      var logMessages = [MenderUpdateError.LogMessage]()

      for try await line in error.lines() {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !line.isEmpty else { continue }

        if line.last == "%", let progress = Int(line.dropLast()) {
          progressCallback?(progress)
        } else if let logMessage = MenderUpdateError.LogMessage(parsing: line) {
          logMessages.append(logMessage)
        }
      }

      let output = try await [String](
        output.lines()
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      ).first

      return (output, logMessages)
    }

    guard process.terminationStatus.isSuccess else {
      switch process.terminationStatus {
      case let .exited(code):
        if let menderUpdateError = MenderUpdateError(
          rawValue: code,
          message: process.value.0,
          logMessages: process.value.1
        ) {
          throw menderUpdateError
        } else {
          throw MenderUpdateError(
            code: .couldNotFulfillRequest,
            message: process.value.0,
            logMessages: process.value.1
          )
        }
      case .unhandledException:
        throw MenderUpdateError.couldNotFulfillRequest
      }
    }
  }

  public func install(
    url: URL,
    stoppingBefore state: State? = nil,
    progressCallback: (@Sendable (Int) -> ())? = nil
  ) async throws {
    try await execute(
      command: .install(url),
      stoppingBefore: state,
      progressCallback: progressCallback
    )
  }

  public func commit(stoppingBefore state: State? = nil) async throws {
    try await execute(command: .commit, stoppingBefore: state)
  }

  public func resume(stoppingBefore state: State? = nil) async throws {
    try await execute(command: .resume, stoppingBefore: state)
  }

  public func rollback(stoppingBefore state: State? = nil) async throws {
    try await execute(command: .rollback, stoppingBefore: state)
  }
}
