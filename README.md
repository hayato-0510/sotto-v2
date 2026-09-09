# Sotto v2

電車の優先席マッチング。「声をかける工程そのものを消す」を狙う。
ユメカタリ 学生生成AIコンテスト 2026・開発部門への応募作品。

## このリポジトリについて

前身の [`sotto`](https://github.com/John-Frusciante/sotto) から作り直している。
**着手前に [`docs/POSTMORTEM.md`](docs/POSTMORTEM.md) を読むこと。** 何が問題で、何を移植したかがまとめてある。

要点だけ書くと：

- 前身の「合言葉（ID）で2端末を接続する」仕組みは、企画の前提（見知らぬ他人同士が無言で繋がる）と
  矛盾していた。**接続方式は未確定として、ここから設計し直す**
- AIパイプライン（`lib/llm.ts` `lib/prompts.ts` `lib/fallback.ts` `lib/speech.ts`）は
  実測・実運用で鍛えられており、そのまま移植した
- UI・接続方式・セッション管理は未着手

開発時の詳細なルールは [`AGENTS.md`](AGENTS.md) を参照。

## セットアップ

```bash
npm install
cp .env.local.example .env.local
# .env.local に GOOGLE_API_KEY を設定（引用符で囲まないこと）
npm run dev
```

## 検証

```bash
npm run check   # typecheck → lint → test → build
npm run try -- "貧血気味で立っているとふらつく" 超満員 3   # UIなしでプロンプトを試す
```
