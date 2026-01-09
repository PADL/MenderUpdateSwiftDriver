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
import MenderUpdateSwiftDriver

// a simple wrapper to exercise the library

func usage(_ argv0: String) -> Never {
  print(
    """
    Usage: \(argv0) [install <url>|commit|resume|rollback]
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

    let driver = MenderUpdateSwiftDriver()
    let command: MenderUpdateSwiftDriver.Command

    switch CommandLine.arguments[1] {
    case "install":
      guard CommandLine.arguments.count >= 3,
            let url = URL(string: CommandLine.arguments[2])
      else {
        usage(CommandLine.arguments[0])
      }

      command = .install(url)
    case "commit":
      command = .commit
    case "resume":
      command = .resume
    case "rollback":
      command = .rollback
    default:
      usage(CommandLine.arguments[0])
    }

    do {
      try await driver.execute(command: command)
    } catch {
      print("error: \(error)")
    }
  }
}
