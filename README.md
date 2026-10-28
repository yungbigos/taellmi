![tällmi: think out loud.](docs/brand/banner/banner.png)

a voice journal for the mac. äh included. <sub>(äh: german for "uh", the sound of thinking.)</sub>

tällmi is a journal you talk to, in any language or a mix of them. it writes down what you say on your mac, keeps every word exactly as you said it, and finds it again later, by word or by meaning.

everything stays on your mac. tällmi itself is built without network access: transcription and search run on models on your mac's own chip. there's no account and no cloud. your thoughts are files, encrypted with a key in your keychain.

the models come in one download, when you press download on first launch. a small downloader inside tällmi fetches them from huggingface.co. it's the only part of tällmi allowed online, and it can't read your thoughts or files. tällmi checks every file against a fixed fingerprint before using it ([why it's built this way](docs/decisions/0016-downloading-models-in-the-app.md)).

it's early. expect rough edges.

## install

download the latest build from [releases](../../releases/latest). you need a mac with apple silicon and macOS 26. on first launch, tällmi asks to download what it needs for speech and search (1.3 GB).

## run from source

with Xcode 26.6:

```bash
brew install xcodegen jq
scripts/download-model.sh parakeet-tdt-0.6b-v3       # speech, once
scripts/download-model.sh qwen3-embedding-0.6b-8bit  # search by meaning, once
scripts/run-app.sh
```

the script downloads the same files the app's download button does, and checks each against a fixed SHA-256. you can skip it and press download on first launch instead.

## more

the plan is in [docs/plan.md](docs/plan.md), every decision in [docs/decisions/](docs/decisions/), and how code is written here in [AGENTS.md](AGENTS.md): every change starts with a failing test.

## support

tällmi is free and made in berlin. if it helps you think, you can [buy me a coffee](https://buymeacoffee.com/yungbigos).

## licence

[MIT](LICENSE)
