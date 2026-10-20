# CSQLiteVec

Vendored [sqlite-vec](https://github.com/asg017/sqlite-vec) **v0.1.9** amalgamation (`sqlite-vec-0.1.9-amalgamation.tar.gz` from the GitHub release), MIT licensed (see `LICENSE-MIT`).

- `sqlite-vec.c` sha256: `ba081a47fa02eadc3cf6b16c314b695b84081269349aac722b4efa338fe8fd85`
- Compiled with `SQLITE_CORE` against the macOS system SQLite, the same library GRDB uses. `AppDatabase.configuration()` registers it on every connection, so no runtime extension loading is needed.
- To upgrade: replace both files with a newer amalgamation, update the version and hash here, run `scripts/check.sh`.
