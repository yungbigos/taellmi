# 0007 — A local MCP server: incoming connections on 127.0.0.1 only

- **Status:** accepted (2026-10-19). Amends AGENTS.md rule 1 ("No network").

## Context

Local LLM clients (LM Studio first) should be able to search and read the Archive through the Model Context Protocol. A sandboxed app cannot be launched as a stdio server by those clients, so the server lives inside the app.

## Decision

- **Transport:** MCP **Streamable HTTP** (spec 2025-11-25, moving to 2026-07-28), served by the app on `127.0.0.1` only. The app gets the `com.apple.security.network.server` entitlement.
- **Still no outgoing network.** The app never gets `network.client`.
- **Off by default.** It is turned on in Settings.
- **Access:**
  - Each client is a config row with its own bearer token (stored in the Keychain).
  - Each client has its own granted tools; anything not granted is denied.
  - The first connection of a new client asks the user in the app.
  - The server validates `Origin` and rejects browser origins.
- **Tools are config** (seeded, editable). Code only implements the tool mechanisms.
  - Read-only tools come first.
  - The "create Entry" tool is off by default and annotated as writing.
  - Entries created through it get Source `mcp:<client>`.
- **Never exposed:** Recordings and encryption keys.
- **Later:** a stdio relay helper for clients that cannot connect to a URL with a header.

## Why

One process holds the data, the future encryption key and the approval UI. A per-client token on loopback is what the spec recommends for local servers, without the weight of OAuth.
