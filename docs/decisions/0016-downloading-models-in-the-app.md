# 0016 — Downloading the voice models in the app, through a downloader that alone may go online

- **Status:** accepted (2026-10-28). Amends AGENTS.md rule 1 ("No outgoing network") and ADR 0007.
- **Issues:** #53.

## Context

tällmi needs two downloads before it can understand you: speech (Parakeet v3, 632 MB) and meaning (Qwen3 embedding, 645 MB). Today the only way to get them is `scripts/download-model.sh`: a terminal, `jq`, a clone of the repo. A new user who opened the disk image has none of that, so their spoken thoughts wait for text forever.

The app cannot download them itself. It has no `com.apple.security.network.client` entitlement (AGENTS.md rule 1), the release workflow refuses to ship one, and a hook blocks adding it. That is on purpose: the app holds your thoughts and runs third-party code (MLX, FluidAudio, swift-transformers, which has its own downloader). Without the entitlement, macOS stops any of it from going online, whatever the code tries.

What a download must do, as the script does:

- fetch each file of a model from Hugging Face at the model's pinned revision (a 40-character commit id, from `Seeds/models.json`);
- check every file against its SHA-256 and size from the model's config, and throw away a file that doesn't match;
- skip files that already match;
- write `.taellmi-verified` with the revision only after every file matched. `ModelInstallation` trusts nothing else.

Hugging Face answers a file request with a redirect, usually to its download servers under `hf.co` (today `us.aws.cdn.hf.co`), sometimes to another path on `huggingface.co`.

## Options

**A. A small downloader inside the app bundle, as an XPC service.** `tällmi.app/Contents/XPCServices/taellmi-downloader.xpc` is a separate program with its own entitlements. macOS starts it when tällmi asks for it and ends it when it is idle or tällmi quits. It gets the network entitlement; tällmi keeps none.

  - An embedded service's entitlements are independent of the app's, in any combination ([Apple forums, Quinn](https://developer.apple.com/forums/thread/847615)). Apple's own sample *SandboxedFetch* is this design: the fetching service has `network.client`, the app doesn't ([sample](https://developer.apple.com/library/archive/samplecode/SandboxingAndNSXPCConnection/Listings/ReadMe_txt.html)).
  - Sparkle, the common Mac update library, ships its downloader the same way, as an XPC service signed ad hoc with the hardened runtime ([Sparkle](https://sparkle-project.org/documentation/sandboxing/)).
  - launchd finds the service by bundle id inside the app, starts it on demand, ends it when idle, and ends it when the app quits ([Creating XPC Services](https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)). An open file can be handed over the connection ([forums](https://developer.apple.com/forums/thread/51592)).
  - Tried on macOS 26 with a throwaway app signed ad hoc like tällmi (2026-10-28): the sandboxed app without the entitlement could not reach huggingface.co ("hostname could not be found"). Its XPC service with `network.client` fetched `parakeet_vocab.json` at the pinned revision, following Hugging Face's redirect, into a file the app had opened and handed over, and the SHA-256 matched `Seeds/models.json`. The service got its own sandbox folder and could not read the app's files.
  - Catches: the service's `Info.plist` needs `XPCService › ServiceType = Application`, which Xcode doesn't generate. The service must link our code statically (the hardened runtime refuses ad hoc signed libraries), and must not use `com.apple.security.inherit` ([forums](https://developer.apple.com/forums/thread/126424)).

**B. Apple's Background Assets.** The system downloads files for an app extension. It doesn't fit tällmi:
  - It needs a downloader extension, an App Group shared with the app, and both signed with an Apple team id ([configuring](https://developer.apple.com/documentation/backgroundassets/configuring-an-unmanaged-background-assets-project), [WWDC23](https://developer.apple.com/videos/play/wwdc2023/10108/)). tällmi is signed ad hoc, without a team; an App Group without one makes macOS ask for access on every launch ([forums](https://developer.apple.com/forums/thread/721701)).
  - It downloads on its own: at install and update, and periodically ([WWDC22](https://developer.apple.com/videos/play/wwdc2022/110403/)); managed asset packs are kept up to date in the background ([WWDC25](https://developer.apple.com/videos/play/wwdc2025/325/)). That breaks "only when you ask".
  - Managed packs must be re-packaged with Apple's `ba-package` tool and hosted by us or Apple (App Store and TestFlight only), not fetched from Hugging Face ([managed packs](https://developer.apple.com/documentation/backgroundassets/creating-managed-asset-packs)). Files live in system storage that may be purged when the disk is low.

**C. A background `URLSession`.** The system process `nsurlsessiond` moves the bytes. Nothing from Apple says the app is then spared the network entitlement ([forums](https://developer.apple.com/forums/thread/744961)). If it worked, it would be a loophole, and "tällmi has no network access" would be misleading.

**D. A login item or launch agent (`SMAppService`).** Can hold the entitlement too, but it is registered with macOS, shows up in Login Items, needs approval in System Settings and keeps running ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)). More than a download needs.

**E. The browser downloads, tällmi imports.** tällmi opens the download page in your browser and you hand the files to tällmi, which checks them. The app stays without any network part, but the two downloads are 25 files in folders: too many to hand over by hand.

**F. A second release file with the models.** The models as one more file on the GitHub release (1.3 GB; GitHub allows up to 2 GiB per file), imported with "add files by hand …". No network part at all, but every model change means a new upload, two downloads for the user, and the GitHub release becomes a mirror we maintain (the licences allow it: CC-BY-4.0 and Apache-2.0). A good fallback to add later, not the main way.

## Decision

**A: a downloader inside the app, as an XPC service, that alone may go online.**

- **What it is:** `taellmi-downloader.xpc` in `Contents/XPCServices`, sandboxed, with exactly two entitlements: `com.apple.security.app-sandbox` and `com.apple.security.network.client`. No file access, no microphone, no contacts, no Keychain. Its code is ours and small: no third-party package is linked into it.
- **tällmi itself never goes online.** The app keeps its entitlements as they are; ML libraries in the app still cannot reach the network.
- **Only when you ask.** tällmi starts the downloader only from the **download** button (the onboarding's voice step now, the voice tab later). Never at launch, never on a schedule, no update checks.
- **Only pinned files from Hugging Face.** The downloader accepts one kind of request: GET `https://huggingface.co/<owner>/<repo>/resolve/<40-hex revision>/<file path>`, without query, port or password. It follows redirects only over https and only to `huggingface.co`, `hf.co` and their subdomains. The allowed hosts are in the downloader's `Info.plist`, so the release check can read them. It sends nothing about you: no cookies, no cache, no stored credentials, no account. Hugging Face sees your IP address and which files were fetched, as with any download, including the script's.
- **It never sees your files.** tällmi opens the file to fill (`<file>.part` in the models folder) and hands the open file to the downloader, which only writes into it. tällmi watches the file grow for the progress bar. The downloader can't open anything of tällmi's itself, and it can't call into tällmi; it only answers.
- **tällmi checks, not the downloader.** When a file is complete, tällmi makes its own copy (a clone on APFS, so it costs no space or time) and checks that copy's size and SHA-256 against the model's config. The downloader may still hold the `.part` open, but never the copy, so it can't change a file after it was checked. A mismatch deletes it and stops that model. After every file matched, tällmi writes `.taellmi-verified` with the revision, exactly like `scripts/download-model.sh`. Files that already match are not fetched again.
- **Which models:** every model assigned to a role whose provider has kind `huggingface` and that isn't verified yet, in role order (speech first). Where the files come from (provider `base_url`, repo, revision, files and hashes) stays config. Changing where tällmi may go online (the allowed hosts) is not config: it needs a new build, because it changes the privacy promise.
- **Right after a model arrives,** thoughts waiting for it are tried again at once instead of after `pipeline.wait_for_model_s`, so a spoken first thought gets its text.
- **It stays alive only while it works.** Each file is one request with an open answer; when the last answer is given, macOS may end it. If tällmi quits, macOS ends it too.
- **The release check allows exactly this.** Every program in the bundle is sandboxed (a program without the sandbox needs no entitlement to go online). The app's own executable has no `network.client`. The downloader is the only program that has it, its entitlements are exactly the two above, both on, and its allowed hosts are exactly `huggingface.co` and `hf.co`. Anything else stops the release. `scripts/check.sh` checks the same on the entitlement files, and the edit hook allows `network.client` in the downloader's entitlement file only.
- **The script stays** for developers, integration tests and anyone who prefers the terminal.

## Why

It keeps the promise that matters: the part of tällmi that holds your thoughts, and all the third-party code in it, can't go online. The one part that can is small, can't read anything, starts only when you press download, can only fetch pinned files from one place, and its work is checked by tällmi before anything is used. A firewall like Little Snitch or LuLu shows it as its own program, `taellmi-downloader`, so you can see or block it separately. It works with ad hoc signing and a disk image, needs no Apple account, is how Apple's own sample and Sparkle do it, and is plain Foundation code we can test.

Background Assets would keep the network out of tällmi's own processes entirely, but it needs an Apple team, an App Group and an App Store-style setup, and it decides on its own when to download.

## Consequences

- **The words change.** README, release notes and the voice step no longer say "the app never goes online". They say: tällmi never goes online; its downloader does, once, when you press download, only to huggingface.co, and every file is checked against its fingerprint.
- **AGENTS.md rule 1** names the downloader as the second exception, next to the MCP server (ADR 0007).
- **What remains possible:** any code in tällmi's process, the third-party libraries included, could open a connection to the downloader itself; macOS doesn't tell the downloader who inside tällmi asked. Through it, such code could only ask huggingface.co for files at a pinned revision. It could hide a little data in the repo or file names it asks for, or fetch a file from a repo someone else controls; tällmi would never use that file, since it matches no fingerprint in tällmi's config. Closing this needs the downloader to accept only the repo and revision pairs from `Seeds/models.json`, written into its `Info.plist` at build time and checked by `scripts/check-network.sh`. That is a possible next step; its cost is that a model added by hand in config would need the script.
- **Building:** the app's bundle id comes from one build setting, `TAELLMI_APP_ID`; the downloader's is `$(TAELLMI_APP_ID).downloader`. `scripts/run-app.sh --demo` and `--fresh` set `TAELLMI_APP_ID` instead of `PRODUCT_BUNDLE_IDENTIFIER`, which would rename the downloader too.
- **Not built yet:**
  - resuming a file after an interruption: a quit or lost connection restarts the file in progress (files already checked are kept);
  - the voice tab's download controls;
  - "add files by hand …": picking a folder of files fetched elsewhere, checked the same way.
