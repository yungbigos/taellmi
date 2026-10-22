![tällmi: think out loud.](docs/brand/banner/banner.png)

a voice journal for the mac. äh included. <sub>(äh: german for "uh", the sound of thinking.)</sub>

tällmi is a journal you talk to, in any language or a mix of them. it writes down what you say on your mac, keeps every word exactly as you said it, and finds it again later, by word or by meaning.

everything stays on your mac. the app is built without network access: transcription and search run on models on your mac's own chip. there's no account and no cloud. your thoughts are files, encrypted with a key in your keychain.

it's early. expect rough edges.

## install

download the latest build from [releases](../../releases/latest). you need a mac with apple silicon and macOS 26. the release notes show how to get the models for speech and search, a step you start yourself.

## run from source

with Xcode 26.6:

```bash
brew install xcodegen jq
scripts/download-model.sh parakeet-tdt-0.6b-v3       # speech, once
scripts/download-model.sh qwen3-embedding-0.6b-8bit  # search by meaning, once
scripts/run-app.sh
```

the model downloads are a step you start yourself, and each file is checked against a fixed SHA-256.

## more

the plan is in [docs/plan.md](docs/plan.md), every decision in [docs/decisions/](docs/decisions/), and how code is written here in [AGENTS.md](AGENTS.md): every change starts with a failing test.

## licence

[MIT](LICENSE)
