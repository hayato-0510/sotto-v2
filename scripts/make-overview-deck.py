# -*- coding: utf-8 -*-
"""作品概要書.md の内容から審査員向けスライド(pptx)を生成する。

  python scripts/make-overview-deck.py docs/作品概要書スライド.pptx

PDF 化は PowerPoint で: Presentations.Open(...).SaveAs(pdf, 32)
"""
import re
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn

INK   = RGBColor(0x1A, 0x1A, 0x1A)
PAPER = RGBColor(0xFA, 0xFA, 0xF7)
FAINT = RGBColor(0x6B, 0x6B, 0x66)
LIVE  = RGBColor(0x2F, 0x6F, 0x4F)
GREENBG = RGBColor(0xEC, 0xF2, 0xEE)
JP = "Yu Gothic"

prs = Presentation()
prs.slide_width  = Inches(13.333)
prs.slide_height = Inches(7.5)
BLANK = prs.slide_layouts[6]
SW, SH = prs.slide_width, prs.slide_height


def set_font(run, name=JP):
    """latin/ea/cs をスキーマ順で設定する。"""
    run.font.name = name  # a:latin
    rPr = run._r.get_or_add_rPr()
    latin = rPr.find(qn("a:latin"))
    for tag in ("a:ea", "a:cs"):
        existing = rPr.find(qn(tag))
        if existing is not None:
            existing.set("typeface", name)
            continue
        el = rPr.makeelement(qn(tag), {"typeface": name})
        latin.addnext(el)
        latin = el


def slide():
    s = prs.slides.add_slide(BLANK)
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = PAPER
    return s


def tf_at(s, x, y, w, h):
    tb = s.shapes.add_textbox(x, y, w, h)
    tf = tb.text_frame
    tf.word_wrap = True
    return tf


def para(tf, text, size, color=INK, bold=False, first=False, sb=8,
         align=PP_ALIGN.LEFT, line=1.3):
    p = tf.paragraphs[0] if first else tf.add_paragraph()
    p.alignment = align
    p.space_before = Pt(0 if first else sb)
    p.line_spacing = line
    for chunk in re.split(r"(\*\*[^*]+\*\*)", text):
        if not chunk:
            continue
        b, t = bold, chunk
        if chunk.startswith("**") and chunk.endswith("**"):
            b, t = True, chunk[2:-2]
        r = p.add_run()
        r.text = t
        r.font.size = Pt(size)
        r.font.bold = b
        r.font.color.rgb = color
        set_font(r)
    return p


def kicker(s, text):
    para(tf_at(s, Inches(0.9), Inches(0.5), Inches(11.5), Inches(0.5)),
         text, 13, FAINT, bold=True, first=True)


def heading(s, text, y=1.0):
    para(tf_at(s, Inches(0.9), Inches(y), Inches(11.5), Inches(1.2)),
         text, 29, INK, bold=True, first=True, line=1.15)


def body(s, lines, y=2.15, w=11.5, size=17, gap=11):
    tf = tf_at(s, Inches(0.9), Inches(y), Inches(w), Inches(5.0))
    for i, ln in enumerate(lines):
        para(tf, ln, size, INK, first=(i == 0), sb=gap, line=1.4)


# 1. Title
s = slide()
tf = tf_at(s, Inches(1.1), Inches(2.2), Inches(11.1), Inches(3.0))
para(tf, "Sotto（ソット）", 40, INK, bold=True, first=True)
para(tf, "席を譲りたい人が、声をかけられないまま、必要な人に席を渡せる。",
     25, LIVE, bold=True, sb=18, line=1.3)
tf = tf_at(s, Inches(1.1), Inches(5.5), Inches(11.1), Inches(1.5))
para(tf, "電車の優先席マッチング（スマートフォンアプリ／Flutter＋ネイティブBLE、今回は Android 版）",
     15, FAINT, first=True)
para(tf, "ユメカタリ 学生生成AIコンテスト 2026・開発部門　｜　2026年9月", 15, FAINT, sb=6)

# 2. 問題
s = slide()
kicker(s, "解こうとしている問題")
heading(s, "譲る意思は約8割ある。それでも座れない。")
body(s, [
    "電車で席を譲る意思を持つ人は約8割。",
    "しかし妊娠7ヶ月の当事者が実際に座れた割合は「片手で数えるほど」に留まる。",
    "",
    "**譲らない理由の1位は「相手に失礼になるかもしれない」46.4%**（内閣府調査）。",
    "「以前に断られた経験がある」が20.4%（エアトリ調査）。",
    "",
    "これは勇気の不足ではなく、**判断を誤るリスク**。呼びかけを何年重ねても減らない。",
])

# 3. 何を作るか
s = slide()
kicker(s, "何を作るか")
heading(s, "一言も交わさずに、席が渡る。")
body(s, [
    "座っている人がアプリを開くと、**すぐ近くに席を必要としている人がいるかどうかだけ**が出る。",
    "［ 譲る ］を押すと、その場の混み具合に合った身体の動きが返る。立って、半歩ずれる。それで終わる。",
], y=2.1)
tf = tf_at(s, Inches(0.9), Inches(3.9), Inches(11.5), Inches(2.4))
para(tf, "3つとも要らない", 15, FAINT, bold=True, first=True)
para(tf, "声をかける工程　／　目線　／　「相手は本当に必要か」という判断",
     21, INK, bold=True, sb=10, line=1.4)

# 4. なぜ譲る側
s = slide()
kicker(s, "設計の中核")
heading(s, "譲る側から「判断」を取り除く。")
body(s, [
    "&HAND / May ii / 声かけ・サポート運動は、9年間ずっと譲る側へ「勇気を出して声をかけよう」と呼びかけてきた。",
    "いずれも譲る側の判断を前提に置いたまま、その判断を下す勇気を求めている。",
    "",
    "Sotto は、譲る側に表示する相手を**自分から「席がほしい」と発信した人だけ**に限る。",
    "相手が席を必要としているかを推測する場面が構造から消えるので、**判断を間違えようがない**。無言化はその上に乗る。",
], y=2.1)

# 5. 体験
s = slide()
kicker(s, "体験（デモ動画の一人称）")
heading(s, "田中は、一度も相手の状態を判断していない。")
steps = [
    ("受け手（佐藤・妊娠初期）", "アプリで「席がほしい」とだけ発信しておく"),
    ("譲る側（田中・学生）", "画面に「すぐ近くに、席を必要としている人がいます」。混み具合を1タップ →［ 譲る ］"),
    ("生成AI", "その場に合った動作を返す（混雑時「立って、座面に手を添えたまま待つ」／空「立って離れて大丈夫」）"),
    ("同じ瞬間", "佐藤の画面が「ごく近くの人が席を空けます」に変わる。田中が立ち、視線を外して半歩ずれる"),
    ("佐藤", "1〜2歩で座り、［ ありがとう ］。田中の画面に「そっと伝わりました」"),
]
tf = tf_at(s, Inches(0.9), Inches(1.95), Inches(11.6), Inches(5.0))
for i, (who, what) in enumerate(steps):
    para(tf, who, 12, LIVE, bold=True, first=(i == 0), sb=13)
    para(tf, what, 15, INK, sb=2, line=1.3)
para(tf, "会話ゼロ・目線ゼロ。押さずに閉じてもよく、そのとき相手は田中が見たことすら知らない（辞退ボタンは無い）。",
     12, FAINT, sb=15)

# 6. 先行事例
s = slide()
kicker(s, "先行事例との違い")
heading(s, "先行事例は判断を前提に置いたまま。Sotto は構造から外す。")
rows = [
    ["比較項目", "ヘルプマーク", "声かけ運動", "&HAND / May ii", "Sotto"],
    ["誰の問題か", "受け手が伝えられない", "譲る側が動かない", "受け手が支援に繋がれない", "譲る側が動けない"],
    ["譲る側への働きかけ", "なし", "呼びかけ（啓発）", "チャットで繋ぐ", "判断そのものを消す"],
    ["声をかける回数", "必要", "必要（それが目的）", "必要", "0回"],
    ["「本当に必要か」の判断", "譲る側が行う", "譲る側が行う", "譲る側が行う", "発生しない"],
]
tW = Inches(11.55)
tbl = s.shapes.add_table(len(rows), 5, Inches(0.9), Inches(2.1), tW, Inches(3.5)).table
tbl.columns[0].width = Inches(2.5)
for c in range(1, 5):
    tbl.columns[c].width = Inches(2.2625)
for ri, row in enumerate(rows):
    tbl.rows[ri].height = Inches(0.6)
    for ci, val in enumerate(row):
        cell = tbl.cell(ri, ci)
        cell.margin_left = Inches(0.1); cell.margin_right = Inches(0.07)
        cell.margin_top = Inches(0.03); cell.margin_bottom = Inches(0.03)
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        cell.fill.solid()
        head = (ri == 0); last = (ci == 4)
        cell.fill.fore_color.rgb = INK if head else (GREENBG if last else PAPER)
        p = cell.text_frame.paragraphs[0]
        r = p.add_run(); r.text = val
        r.font.size = Pt(10.5)
        r.font.bold = head or last or (ci == 0)
        r.font.color.rgb = PAPER if head else (LIVE if last else INK)
        set_font(r)
para(tf_at(s, Inches(0.9), Inches(6.0), Inches(11.5), Inches(0.8)),
     "決定的な違いは最下段。Sotto は判断そのものを構造から取り除く。", 12, FAINT, first=True)

# 7. 生成AI
s = slide()
kicker(s, "なぜ生成AIが必要か（「通知と if 文で足りるのでは」への回答）")
heading(s, "選択肢で網羅できない3つを、生成で埋める。")
ai = [
    ("AI-1　自由記述の解読", "「貧血で立っていられない」「ギプスで座ると逆に痛い」— 困りごとは無限。自由テキストを構造データへ正規化する"),
    ("AI-2　混雑度に応じた身体動作の生成", "空いている時と超満員では正解の動作が真逆。この分岐が本作の性格を決めるダイヤルで、事前にルール化しきれない"),
    ("AI-3　語気の調律", "「席を譲ってください」の命令形は義務感を生み、断る自由を奪う。善意を搾取しない語気を生成する"),
]
tf = tf_at(s, Inches(0.9), Inches(2.0), Inches(11.6), Inches(4.0))
for i, (h, d) in enumerate(ai):
    para(tf, h, 17, LIVE, bold=True, first=(i == 0), sb=15)
    para(tf, d, 14, INK, sb=2, line=1.35)
para(tf, "安全側の要件：出力に発話の指示が混ざるとプロダクトの存在理由が壊れる。AIの出力はサーバ側で必ず検証し、該当したら固定文へ差し替える。ここだけはAI任せにしない。",
     12, FAINT, sb=16, line=1.4)

# 8. 実装状況
s = slide()
kicker(s, "実装状況（2026年9月）")
heading(s, "Android 版を実装。実機2台で通し確認まで済んでいる。")
body(s, [
    "**AIサーバ**（Next.js / TypeScript）— Vercel で稼働。状態を持たず、需要はサーバ鍵で封緘して受け手の端末が保持",
    "**アプリ**（Flutter ＋ 自作プラットフォームチャネル越しのネイティブBLE / Kotlin）",
    "**受け渡しの同期は BLE 直結（GATT）で確定** — 2台が到達圏内なので端末間で直接渡す。リアルタイムサービスは不要",
    "",
    "**実機2台（Android 12 / 13）で手動確認 §0〜§5 が室内・近距離で成立**",
    "　役割選択・AI要約・発信・近接検知・混み具合に応じた動作生成・2台間の受け渡し・お礼まで通った",
], y=2.1, size=15, gap=10)

# 9. 未解決の論点
s = slide()
kicker(s, "未解決の論点（検証していない前提を確定事項として扱わない）")
heading(s, "残っている検証と、既知の制約。")
pts = [
    ("近接検知の実機精度【一部確認】",
     "室内・近距離では実機2台で成立。距離ごとの分布・ポケット内・混雑車内・背景発信30分は未検証。受け渡しを短い間隔で連続すると接続が落ちる（再接続のバックオフで回避可能）"),
    ("当面は同一OS間に限る",
     "iOS が背景で発信するサービスIDは Apple 独自の領域に入り Android から検出できない。接触確認アプリが OS の専用APIになったのと同じ壁。画面にも明示する"),
    ("混雑時の身体動作の心理的抵抗【要確認】",
     "「座面に手を添えて待つ」をやってもらえるかは未測定。旧案（緑に光って立ちはだかる）は廃止し、この動作は混雑時のみに縮小した"),
    ("利用者が少ない時期の目立ちやすさ",
     "周囲に発信端末が1台だけだと発信自体が目立つ。識別子の定期更新・移動中のみ発信は設計済みだが未解決"),
]
tf = tf_at(s, Inches(0.9), Inches(1.95), Inches(11.7), Inches(5.0))
for i, (h, d) in enumerate(pts):
    para(tf, h, 15, INK, bold=True, first=(i == 0), sb=12)
    para(tf, d, 12, FAINT, sb=2, line=1.3)

# 10. 資料
s = slide()
kicker(s, "詳細資料")
heading(s, "この一枚の裏にある文書")
body(s, [
    "要求定義書 — なぜ・誰のために・何を目指すか",
    "要件定義書 — システムが何をしなければならないか（FR / NFR）",
    "設計書 — どう作るか（接続方式の判断、技術選定、暫定値）",
    "スパイク手順書 / spike-results — 実機検証の手順と結果",
    "POSTMORTEM — 前身リポジトリでの失敗と、そこから持ち越したもの",
    "デモ動画構成 — 応募用デモ（約1分）の構成と撮り方",
], y=2.1, size=15, gap=10)

import sys
out = sys.argv[1]
prs.save(out)
print("saved", out)
