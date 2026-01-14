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

import Foundation
import Logging
import MenderUpdateSwiftDriver

// a simple wrapper to exercise the library

func usage(_ argv0: String) -> Never {
  print(
    """
    Usage: \(argv0) [install <url>|commit|resume|rollback|show-artifact|show-provides]
    """
  )
  exit(2)
}

@main
public actor MenderUpdateSwiftDriverWrapper {
  public static func main() async {
    guard CommandLine.arguments.count >= 2 else {
      usage(CommandLine.arguments[0])
    }

    LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }

    var logger = Logger(label: "com.padl.MenderUpdateSwiftDriverWrapper")
    logger.logLevel = .debug

    let driver = MenderUpdateSwiftDriver(options: .init(logLevel: logger.logLevel), logger: logger)

    do {
      switch CommandLine.arguments[1] {
      case "install":
        guard CommandLine.arguments.count >= 3,
              let url = URL(string: CommandLine.arguments[2])
        else {
          usage(CommandLine.arguments[0])
        }

        let progressCallback = { @Sendable (_: Int) in
          if let data = ".".data(using: .utf8) {
            try? FileHandle.standardOutput.write(contentsOf: data)
          }
        }

        try await driver.install(url: url, progressCallback: progressCallback)
        print() // Print newline after installation completes
      case "commit":
        try await driver.commit()
      case "resume":
        try await driver.resume()
      case "rollback":
        try await driver.rollback()
      case "show-artifact":
        let artifact = try await driver.showArtifact()
        print(artifact)
      case "show-provides":
        let provides = try await driver.showProvides()
        for line in provides {
          print(line)
        }
      default:
        usage(CommandLine.arguments[0])
      }
    } catch {
      print("error: \(error)")
    }
  }
}
