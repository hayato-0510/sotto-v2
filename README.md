# Sotto v2

> **席を譲りたい人が、声をかけられないまま、必要な人に席を渡せる。**

電車の優先席マッチング。主役は譲る側 — 譲りたいのに気まずくて動けない人。ゴールは受け手が座ること。

## いまどこまで決まっているか

**体験の設計は確定した。技術の選定はまだ何も決まっていない。**

- 接続方式は**近接検知（ネイティブアプリの BLE）で確定**。合言葉・号車番号・GPS・QRコードはいずれも却下した
- マッチングは**数m以内の隣接した人同士**に限る。これで車内の横断移動と席のキープが不要になった
- 譲る側に push 通知で割り込まない（**プル型**）。自分でアプリを開いた人に、近くの需要だけを見せる
- 表示するのは**自分から「席がほしい」と発信した人だけ**。譲る側が「相手は本当に必要か」を判断する場面が構造から消える
- 構成は **Flutter（UI 9画面）＋ 自作プラットフォームチャネル越しのネイティブBLE ＋ 現状の Node/TS を AI サーバとして継続**
- **今回作るのは Android 版のみ。** iOS は次フェーズ（UI は Flutter なので画面の作り直しは発生しない）
- BLE の詳細と受け渡しの同期手段は未確定。**同期は BLE 直結で足りる可能性があり**、そうなればリアルタイムサービスが不要になる

**近接検知の実機精度は未検証。** 実装より先にスパイクを行う。RSSI で数m判定が安定するか、背景での
発信が何分続くか、2台間の GATT で Handoff を直接渡せるか。ここが駄目なら設計の土台から書き直しになる。

**当面のマッチング動作保証は同一OS間に限る。** iOS が背景で発信するサービスIDは Apple 独自の領域に
入り Android から検出できないため（[`docs/設計書.md`](docs/設計書.md) §1.5.1）。この制約は UI にも明示する。

## ドキュメント

読む順番は上から。

| 文書 | 中身 |
| :--- | :--- |
| [`docs/POSTMORTEM.md`](docs/POSTMORTEM.md) | 前身リポジトリ [`sotto`](https://github.com/John-Frusciante/sotto) で何を間違えたか。**着手前に読む** |
| [`docs/要求定義書.md`](docs/要求定義書.md) | なぜ・誰のために・何を目指すか |
| [`docs/要件定義書.md`](docs/要件定義書.md) | システムが何をしなければならないか（FR / NFR） |
| [`docs/設計書.md`](docs/設計書.md) | どう作るか。**§7 が「技術選定・未着手」の空欄** |
| [`docs/スパイク手順書.md`](docs/スパイク手順書.md) | **実装より先に回す検証**の手順・合格基準・落ちたときの戻り先 |
| [`docs/作品概要書.md`](docs/作品概要書.md) | 審査員向けの一枚要約 |
| [`docs/体験再設計-作業メモ.md`](docs/体験再設計-作業メモ.md) | 今回の再設計で採用しなかった案と、その理由 |

開発時のルールは [`AGENTS.md`](AGENTS.md) を参照。

## 移植済みのコード

前身から**使える部分だけ**を持ってきてある。UI とセッション管理はゼロから作る。

`lib/llm.ts`（Gemini/Anthropic 抽象化・モデル選定・リトライ）、`lib/prompts.ts`（実運用で3回チューニング済み）、
`lib/speech.ts` と `lib/fallback.ts`（発話混入の検出とフォールバック＝**プロダクトの安全根幹**）、
`lib/types.ts`、`scripts/try.mjs`。

## 現在の実装状態（2026-09-10）

AI サーバ（`app/api/*`、`lib/*.ts`）と Flutter アプリ（`mobile/`）の両方がある。
**実機での近接検知は未検証。** 実機不在のままスパイクを飛ばして実装した経緯と暫定値は
[`docs/開発計画.md`](docs/開発計画.md) と [`docs/設計書.md`](docs/設計書.md) §7.2.1、実機での確認手順は
[`docs/手動確認.md`](docs/手動確認.md) にある。

| エンドポイント | 役割 |
| :--- | :--- |
| `POST /api/needs` | ステップ1：状態テキスト → Needs |
| `POST /api/demands` | 本人が確認した Needs をサーバ鍵で封緘して返す。サーバは何も保存しない |
| `POST /api/handoff` | ステップ2：封緘 ＋ 混雑度 → Handoff（発話検証つき） |
| `GET /api/health` | 疎通確認（鍵の値は返さない） |

需要の中身は封緘されたまま受け手の端末が持ち、BLE（GATT）で譲る側の端末へ渡り、サーバでだけ復号される。
譲る側の端末は Needs を一度も復号できない。

## セットアップ

```bash
npm install
cp .env.local.example .env.local
# .env.local に GOOGLE_API_KEY を設定（引用符で囲まないこと）
```

## 検証

```bash
npm run check   # typecheck → lint → test → build
npm run try -- "貧血気味で立っているとふらつく" 超満員 3   # UIを経由せずプロンプトを試す
npm run smoke -- http://localhost:3000                   # 4本のエンドポイントを順に叩く（デプロイ先のURLも可）
npm run pregenerate                                       # 審査用の混雑度対比データを mobile/assets に生成
cd mobile && flutter analyze && flutter test              # アプリ側
```

## デプロイ（Vercel）と APK

```bash
vercel login
vercel --prod
```

Vercel の Environment Variables に `GOOGLE_API_KEY` と `SOTTO_BLOB_KEY`（`.env.local.example` 参照）を登録して再デプロイし、
`npm run smoke -- https://<デプロイ先>` で `provider=google blobKey=set` を確認する。

**`.env.local` から値を流し込むときは、引用符と `\r` を落とすこと。** Next の env ローダは値を囲む引用符を
剥がすのでローカルでは動くが、`vercel env add` に渡すと引用符ごと登録されて鍵が無効になり、生成がすべて
定型文に落ちる（実際に踏んだ。CRLF の `\r` も同じ）。`smoke` で「（定型）」が並ぶのに `provider=google` なら、
SDK を疑う前に、取り出した値そのもので Gemini の REST を叩いて鍵を検証する（200 以外なら取り出し方が悪い）：

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "x-goog-api-key: $(grep '^GOOGLE_API_KEY=' .env.local | cut -d= -f2- | tr -d '\r\n' | sed -E 's/^(["'"'"'])(.*)\1$/\2/')" https://generativelanguage.googleapis.com/v1beta/models
```

`SOTTO_BLOB_KEY` は本番では必須で、無いと `/api/demands` と `/api/handoff` が失敗する（固定鍵で代替しない）。

```bash
grep '^GOOGLE_API_KEY=' .env.local | cut -d= -f2- | tr -d '\r\n' | sed -E 's/^(["'"'"'])(.*)\1$/\2/' | vercel env add GOOGLE_API_KEY production
```

アプリはデプロイ先の URL を埋め込んでビルドする：

```bash
cd mobile && flutter build apk --release --dart-define=SOTTO_API_BASE=https://<デプロイ先>
```
