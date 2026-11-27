# Sotto v2

> **席を譲りたい人が、声をかけられないまま、必要な人に席を渡せる。**

電車の優先席マッチング。主役は譲る側 — 譲りたいのに気まずくて動けない人。ゴールは受け手が座ること。

## いまどこまで来ているか

**体験の設計は確定。Android 版を実装し、実機2台で通し確認まで済んでいる。**

- 接続方式は**近接検知（ネイティブアプリの BLE）**。合言葉・号車番号・GPS・QRコードはいずれも却下した
- マッチングは**数m以内の隣接した人同士**に限る。これで車内の横断移動と席のキープが不要になった
- 譲る側に push 通知で割り込まない（**プル型**）。自分でアプリを開いた人に、近くの需要だけを見せる
- 表示するのは**自分から「席がほしい」と発信した人だけ**。譲る側が「相手は本当に必要か」を判断する場面が構造から消える
- 構成は **Flutter（UI）＋ 自作プラットフォームチャネル越しのネイティブBLE ＋ Node/TS の AI サーバ**
- **今回作るのは Android 版のみ。** iOS は次フェーズ（UI は Flutter なので画面の作り直しは発生しない）
- **受け渡しの同期は BLE 直結（GATT）で確定。** 2台が到達圏内なので Handoff を端末間で直接渡す。リアルタイムサービスは不要になった

**近接検知は室内・近距離では実機2台で成立した**（[`docs/spike-results.md`](docs/spike-results.md)）。
RSSI で近距離と5m＋壁越しを分けられ、2台間の GATT で Handoff も往復し、[`docs/手動確認.md`](docs/手動確認.md) §0〜§5 が通った。
ただし距離ごとの分布・ポケット内・電車内・背景発信30分は未検証で、
ここが駄目なら設計の土台から書き直しになる点は変わらない（残りの検証は GitHub Issue #2〜#6）。

**当面のマッチング動作保証は同一OS間に限る。** iOS が背景で発信するサービスIDは Apple 独自の領域に
入り Android から検出できないため（[`docs/設計書.md`](docs/設計書.md) §1.5.1）。この制約は UI にも明示する。

## 画面と体験の流れ

アプリの画面は、声かけと判断を消すために最小限に絞ってあります。

| 場面 | 画面で起きること |
| :--- | :--- |
| 受け手（席がほしい人） | アプリで「席がほしい」とだけ発信しておく。自由記述の困りごとは生成AIが構造データへ正規化する |
| 譲る側（座っている人） | アプリを開くと、すぐ近くに席を必要としている人がいるかどうかだけが出る。相手を選んだり、要否を判断したりする画面はない |
| 譲る瞬間 | ［譲る］を1タップすると、その場の混み具合に合った身体の動作が返る（例: 立って、座面に手を添えたまま待つ）。発話は含まれない |
| 受け手の画面 | 「ごく近くの人が席を空けます」に変わる。譲る側が立ち、視線を外して半歩ずれるので、そのまま座れる |
| 終わり | 受け手が「ありがとう」を送ると、譲る側に「そっと伝わりました」と出る。会話も目線も発生しない |

マッチングは BLE の近接検知で数m以内の相手に限ります。受け渡しの同期も端末同士の直接通信（GATT）で行い、サーバは生成AIの処理だけを担います。

## 技術構成

| 部分 | 技術 |
| :--- | :--- |
| アプリ | Flutter（Android）＋自作プラットフォームチャネル越しのネイティブ BLE（Kotlin） |
| AI サーバ | Next.js / TypeScript（Vercel）。自由記述の正規化、混雑度に応じた動作生成、語気の調律を行い、出力はサーバ側で検証してから返す |
| 同期 | BLE 直結（GATT）。リアルタイムサービスは使わない |

実機2台（Android 12 / 13）で、役割選択・AI要約・発信・近接検知・混み具合に応じた動作生成・2台間の受け渡し・お礼まで通しで確認済みです（[`docs/spike-results.md`](docs/spike-results.md)）。

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
| [`docs/作品概要書スライド.md`](docs/作品概要書スライド.md) | 上をスライド10枚にまとめたもの（`.pptx` / `.pdf` あり） |
| [`docs/デモ動画構成.md`](docs/デモ動画構成.md) | 応募用デモ動画（約1分）の構成と撮り方。**デモの流れはこれを正とする** |
| [`docs/ナレーション台本.md`](docs/ナレーション台本.md) | 応募テーマ、デモ動画・presentation動画のナレーション（尺つき） |
| [`docs/spike-results.md`](docs/spike-results.md) | 実機2台での検証結果。室内・近距離で §0〜§3 が成立。残る検証項目もここ |
| [`docs/体験再設計-作業メモ.md`](docs/体験再設計-作業メモ.md) | 今回の再設計で採用しなかった案と、その理由 |

開発時のルールは [`AGENTS.md`](AGENTS.md) を参照。

## 移植済みのコード

前身から**使える部分だけ**を持ってきてある。UI とセッション管理はゼロから作る。

`lib/llm.ts`（Gemini/Anthropic 抽象化・モデル選定・リトライ）、`lib/prompts.ts`（実運用で3回チューニング済み）、
`lib/speech.ts` と `lib/fallback.ts`（発話混入の検出とフォールバック＝**プロダクトの安全根幹**）、
`lib/types.ts`、`scripts/try.mjs`。

## 現在の実装状態（2026-09-10）

AI サーバ（`app/api/*`、`lib/*.ts`）と Flutter アプリ（`mobile/`）の両方がある。
**室内・近距離では実機2台で通し確認が成立（[`docs/spike-results.md`](docs/spike-results.md)）。** 距離分布・ポケット内・電車内・背景発信の持続は未検証。実機不在のままスパイクを飛ばして実装した経緯と暫定値は
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
