//
// Copyright (c) 2025 PADL Software Pty Ltd
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
}

public struct MenderUpdateError: Error, Sendable {
  public enum Code: Subprocess.TerminationStatus.Code, Sendable {
    case couldNotFulfillRequest = 1
    case noUpdateInProgress = 2
    case reboot = 4
  }

  public let code: Code
  public let info: String?

  fileprivate init(code: Code, info: String? = nil) {
    self.code = code
    self.info = info
  }

  fileprivate init?(rawValue code: Subprocess.TerminationStatus.Code, info: String? = nil) {
    guard let code = Code(rawValue: code) else {
      return nil
    }
    self.init(code: code, info: info)
  }

  fileprivate static let couldNotFulfillRequest = Self(code: .couldNotFulfillRequest)
  fileprivate static let noUpdateInProgress = Self(code: .noUpdateInProgress)
  fileprivate static let reboot = Self(code: .reboot)
}

private extension Subprocess.CollectedResult where Output == StringOutput<UTF8>,
  Error == StringOutput<UTF8>
{
  func throwOnError() throws {
    guard !terminationStatus.isSuccess else { return }
    switch terminationStatus.self {
    case let .exited(code):
      if let menderUpdateError = MenderUpdateError(rawValue: code, info: standardError) {
        throw menderUpdateError
      } else {
        throw MenderUpdateError(code: .couldNotFulfillRequest, info: standardError)
      }
    case .unhandledException:
      throw MenderUpdateError.couldNotFulfillRequest
    }
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
      arguments += ["--log-file", logLevel._menderLogLevel]
      if let trustedCerts { arguments += ["--trusted-certs", trustedCerts] }
      if skipVerify { arguments += ["--skipverify"] }

      return arguments
    }
  }

  private let _binaryPath: FilePath
  private let _options: Options

  private func _menderUpdateArguments(
    command: Command,
    stoppingBefore state: State? = nil
  ) -> Subprocess.Arguments {
    // mender-update [global options] command [command options] [arguments...]

    var arguments: [String] = _options._menderUpdateArguments + [command._menderUpdateCommand]

    if case .install = command {
      arguments += ["--reboot-exit-code"]
    } else if command == .resume {
      arguments += ["--reboot-exit-code"]
    }

    if let state {
      arguments += ["-stop-before", String(describing: state)]
    }

    return .init(arguments)
  }

  public init(options: Options = .init(), binaryPath: FilePath = "/usr/bin/mender-update") {
    _options = options
    _binaryPath = binaryPath
  }

  package func execute(command: Command, stoppingBefore state: State? = nil) async throws {
    let arguments = _menderUpdateArguments(command: command, stoppingBefore: state)
    let process = try await Subprocess.run(
      .path(_binaryPath),
      arguments: arguments,
      output: .string(limit: Int(BUFSIZ)),
      error: .string(limit: Int(BUFSIZ)),
    )
    try process.throwOnError()
  }

  public func install(url: URL, stoppingBefore state: State? = nil) async throws {
    try await execute(command: .install(url), stoppingBefore: state)
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
