# Third-party notices

The project's own code is distributed under the MIT license. Dependencies retain their own licenses.

- [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle): its license is retained in `Resources/Sparkle-LICENSE.txt` and embedded in the application.
- [SwiftTerm 1.20.0](https://github.com/migueldeicaza/SwiftTerm): MIT; the full copyright and license notices are in `Resources/SwiftTerm-LICENSE.txt` and embedded in the application.
- Rust dependencies, including SQLx, Tokio, Redis, Reqwest, SQLParser and their transitive dependencies, are pinned in `engine/Cargo.lock`. Available locked crate license texts are collected into `Resources/Rust-THIRD-PARTY-LICENSES.txt` for the source and application distribution. Platform-specific crates not built on this machine link to their upstream crate sources.
- `/usr/bin/ssh`, `/usr/bin/sftp` and `/bin/zsh` are system executables supplied by macOS. They are invoked as separate processes and are not redistributed by this project.

The Sparkle Ed25519 verification key is public verification material. No signing private keys or credentials are distributed.

Launcher layout and Shell UI are adapted from the user-owned anjing-financex and [anjing-shell](https://github.com/anjing-le/anjing-shell) projects with explicit user authorization. Private cursor artwork and mock server content are excluded.
