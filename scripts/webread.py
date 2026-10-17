#!/usr/bin/env python3
"""Read AtCoder tasks and GitHub pages in a terminal."""

import argparse
from dataclasses import dataclass, field
from html import escape
from html.parser import HTMLParser
import re
import shutil
import subprocess
import sys
from urllib.parse import parse_qs, quote, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen


@dataclass
class Element:
    tag: str
    attrs: dict = field(default_factory=dict)
    children: list = field(default_factory=list)

    def find(self, predicate):
        if predicate(self):
            return self
        for child in self.children:
            if isinstance(child, Element):
                found = child.find(predicate)
                if found:
                    return found
        return None

    def text(self):
        return "".join(child.text() if isinstance(child, Element) else child for child in self.children)


class Document(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "wbr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Element("document")
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Element(tag, dict(attrs))
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.stack.pop()

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)


SYMBOLS = {
    "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠",
    "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓",
    "infty": "∞", "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆",
    "cup": "∪", "cap": "∩", "sum": "Σ", "prod": "Π", "forall": "∀", "exists": "∃",
    "ldots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "dots": "…", "to": "→", "rightarrow": "→",
    "leftarrow": "←", "Rightarrow": "⇒", "iff": "⇔", "oplus": "⊕", "land": "∧", "lor": "∨",
    "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "mid": "|",
    "vert": "|", "lvert": "|", "rvert": "|", "quad": " ", "qquad": "  ",
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "theta": "θ", "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "phi": "φ", "omega": "ω",
}
SUB = str.maketrans("0123456789+-=()ainx", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐᵢₙₓ")
SUPER = str.maketrans("0123456789+-=()in", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁱⁿ")


def group(source, start):
    """Read a braced TeX argument, or a single unbraced character."""
    if start >= len(source):
        return "", start
    if source[start] != "{":
        return source[start], start + 1
    depth = 1
    i = start + 1
    while i < len(source) and depth:
        depth += (source[i] == "{") - (source[i] == "}")
        i += 1
    return source[start + 1:i - 1] if depth == 0 else source[start:], i


def math_text(source):
    """Make common AtCoder TeX readable; retain unknown commands verbatim."""
    source = re.sub(r"(?<!\w)/vdots\b", r"\\vdots", source)
    out = []
    i = 0
    while i < len(source):
        char = source[i]
        if char == "\\":
            match = re.match(r"\\([A-Za-z]+|.)", source[i:])
            if not match:
                out.append(char)
                i += 1
                continue
            command = match.group(1)
            i += len(match.group(0))
            if command in ("frac", "dfrac", "tfrac", "binom") and i < len(source):
                first, i = group(source, i)
                second, i = group(source, i)
                out.append(f"({math_text(first)})/({math_text(second)})" if command != "binom"
                           else f"C({math_text(first)}, {math_text(second)})")
            elif command == "sqrt" and i < len(source):
                arg, i = group(source, i)
                out.append(f"√({math_text(arg)})")
            elif command in ("text", "mathrm", "mathbf", "mathit", "operatorname") and i < len(source):
                arg, i = group(source, i)
                out.append(math_text(arg))
            elif command in ("left", "right"):
                pass
            elif command in SYMBOLS:
                out.append(SYMBOLS[command])
            elif command in ("{", "}", "_", "^", "%", "&", "#", "$", "\\"):
                out.append(command)
            else:
                out.append("\\" + command)
        elif char in "_^":
            arg, i = group(source, i + 1)
            converted = math_text(arg)
            table = SUB if char == "_" else SUPER
            supported = "0123456789+-=()ainx" if char == "_" else "0123456789+-=()in"
            if all(c in supported for c in converted):
                out.append(converted.translate(table))
            elif char == "_":
                out.append(f"[{converted}]")
            else:
                out.append(f"^({converted})")
        elif char in "{}":
            i += 1
        else:
            out.append(char)
            i += 1
    return "".join(out).strip()


MATH = re.compile(r"\\\((.+?)\\\)|\\\[(.+?)\\\]|\$\$(.+?)\$\$|(?<!\\)\$(.+?)\$", re.S)


def bare_math(value):
    """Handle TeX tokens that appear without a math delimiter in AtCoder HTML."""
    value = re.sub(r"(?<!\w)/vdots\b", "⋮", value)
    value = re.sub(r"\\[A-Za-z]+", lambda m: SYMBOLS.get(m.group()[1:], m.group()), value)
    pattern = r"(?<![\w\\])([A-Za-z][A-Za-z0-9]*)([_^])({[^{}]+}|[A-Za-z0-9])"

    def convert(match):
        base, operator, arg = match.groups()
        value = arg[1:-1] if arg.startswith("{") else arg
        table = SUB if operator == "_" else SUPER
        allowed = "0123456789+-=()ainx" if operator == "_" else "0123456789+-=()in"
        if all(c in allowed for c in value):
            return base + value.translate(table)
        return base + f"[{math_text(value)}]" if operator == "_" else base + f"^({math_text(value)})"

    return re.sub(pattern, convert, value)


def render_text(value):
    parts = []
    last = 0
    for match in MATH.finditer(value):
        parts.append(escape(bare_math(value[last:match.start()])))
        converted = escape(math_text(next(group for group in match.groups() if group is not None)))
        inline = match.group(1) is not None or match.group(4) is not None
        parts.append(f"<strong>{converted}</strong>" if inline else f"<div><strong>{converted}</strong></div>")
        last = match.end()
    parts.append(escape(bare_math(value[last:])))
    return "".join(parts)


def render_node(node, literal=False, pre_math=False):
    if isinstance(node, str):
        return escape(node) if literal else render_text(node)
    if node.tag == "script" and node.attrs.get("type", "").startswith("math/tex"):
        content = escape(math_text(node.text()))
        return f"<div><strong>{content}</strong></div>" if "display" in node.attrs.get("type", "") else f"<strong>{content}</strong>"
    if node.tag in {"script", "style", "noscript", "button", "form", "textarea", "iframe", "svg"}:
        return ""
    classes = set(node.attrs.get("class", "").split())
    if "div-btn-copy" in classes:
        return ""
    if node.tag == "img":
        return escape(node.attrs.get("alt") or "[image]")
    attrs = ""
    for key in ("href", "id"):
        if key in node.attrs and node.attrs[key] is not None:
            attrs += f' {key}="{escape(node.attrs[key], quote=True)}"'
    if node.tag == "section":
        heading = next((child.text().strip() for child in node.children
                        if isinstance(child, Element) and child.tag == "h3"), "")
        pre_math = heading in {"入力", "出力", "Input", "Output"}
    child_literal = literal or node.tag == "code" or (node.tag == "pre" and not pre_math)
    content = "".join(render_node(child, child_literal, pre_math) for child in node.children)
    if node.tag in Document.VOID:
        return f"<{node.tag}{attrs}>"
    return f"<{node.tag}{attrs}>{content}</{node.tag}>"


def atcoder_html(source, url, lang):
    doc = Document()
    doc.feed(source)
    statement = doc.root.find(lambda n: n.attrs.get("id") == "task-statement")
    if statement is None:
        raise ValueError("AtCoder の問題文が見つかりません。URL とログイン状態を確認してください")
    selected = statement.find(lambda n: f"lang-{lang}" in n.attrs.get("class", "").split())
    if selected is None:
        if statement.find(lambda n: "lang-ja" in n.attrs.get("class", "").split()
                          or "lang-en" in n.attrs.get("class", "").split()):
            raise ValueError(f"{lang} の問題文がありません")
        selected = statement
    title_node = doc.root.find(lambda n: n.tag == "title")
    title = title_node.text().split(" - AtCoder")[0].strip() if title_node else url
    base = escape(url, quote=True)
    return f'<!doctype html><html><head><meta charset="utf-8"><base href="{base}"></head><body><h1>{escape(title)}</h1>{render_node(selected)}</body></html>'


def fetch_page(url):
    request = Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; webread/1.0)"})
    with urlopen(request, timeout=15) as response:
        source = response.read().decode(response.headers.get_content_charset() or "utf-8", errors="replace")
        return source, response.geturl()


def document_html(source, url):
    doc = Document()
    doc.feed(source)
    host = urlparse(url).hostname
    if host == "atcoder.jp":
        content = doc.root.find(lambda n: n.attrs.get("id") == "main-container")
    else:
        content = doc.root.find(lambda n: n.tag == "article" and len(n.text().strip()) > 100)
        content = content or doc.root.find(lambda n: n.tag == "main" and len(n.text().strip()) > 100)
    if content is None:
        raise ValueError("解説本文を抽出できませんでした")
    title_node = doc.root.find(lambda n: n.tag == "title")
    title = title_node.text().strip() if title_node else "解説"
    return (f'<!doctype html><html><head><meta charset="utf-8"><base href="{escape(url, quote=True)}">'
            f'</head><body><h1>{escape(title)}</h1>{render_node(content)}</body></html>')


def editorial_links(source, listing_url):
    """Get task-specific links in page order, stopping before overall editorials."""
    doc = Document()
    doc.feed(source)
    contest = urlparse(listing_url).path.split("/")[2]
    found = []
    overall = False

    def visit(node):
        nonlocal overall
        if overall or isinstance(node, str):
            return
        if node.tag in {"h2", "h3", "h4"} and re.search(r"コンテスト全体の解説|Overall Editorial", node.text(), re.I):
            overall = True
            return
        if node.tag == "li":
            anchors = []

            def collect(child):
                if isinstance(child, str):
                    return
                if child.tag == "a":
                    anchors.append(child)
                for grandchild in child.children:
                    collect(grandchild)

            collect(node)
            for anchor in anchors:
                href = anchor.attrs.get("href", "")
                absolute = urljoin(listing_url, href)
                parsed = urlparse(absolute)
                article = parsed.hostname == "atcoder.jp" and re.fullmatch(
                    rf"/contests/{re.escape(contest)}/editorial/\d+/?", parsed.path)
                jump = parsed.hostname == "atcoder.jp" and parsed.path == "/jump"
                if article or jump:
                    if jump:
                        absolute = parse_qs(parsed.query).get("url", [absolute])[0]
                    label = " ".join(node.text().split())
                    found.append((absolute, label, bool(re.search(r"公式|Official", label, re.I))))
                    break
            return
        for child in node.children:
            visit(child)

    root = doc.root.find(lambda n: n.attrs.get("id") == "main-container") or doc.root
    visit(root)
    return found


def editorial_list_html(links, listing_url):
    items = "".join(f'<li><a href="{escape(url, quote=True)}">{escape(label)}</a></li>'
                    for url, label, _ in links)
    if not items:
        items = "<li>この問題の解説が見つかりませんでした。</li>"
    return (f'<!doctype html><html><head><meta charset="utf-8"><base href="{escape(listing_url, quote=True)}">'
            f'</head><body><h1>解説一覧</h1><ul>{items}</ul></body></html>')


def view_editorial(task_url, lang, dump, list_only):
    parsed = urlparse(task_url)
    listing_url = urlunparse(parsed._replace(path=parsed.path.rstrip("/") + "/editorial",
                                             query=f"lang={lang}", fragment=""))
    listing, _ = fetch_page(listing_url)
    links = editorial_links(listing, listing_url)
    if list_only or not links:
        view_html(editorial_list_html(links, listing_url), dump)
        return
    chosen = min(links, key=lambda link: (
        not link[2], urlparse(link[0]).hostname != "atcoder.jp"))
    try:
        source, final_url = fetch_page(chosen[0])
        markup = document_html(source, final_url)
    except (OSError, ValueError):
        markup = editorial_list_html(links, listing_url)
    view_html(markup, dump)


def run(command, data=None):
    try:
        result = subprocess.run(command, input=data, check=False)
    except FileNotFoundError:
        raise ValueError(f"必要なコマンドがありません: {command[0]}") from None
    if result.returncode:
        raise ValueError(f"{command[0]} が終了コード {result.returncode} で失敗しました")


def view_html(markup, dump):
    if not shutil.which("w3m"):
        raise ValueError("w3m が必要です: sudo apt install w3m")
    run(["w3m", "-T", "text/html", "-I", "UTF-8", "-O", "UTF-8",
         "-o", "confirm_qq=0", "-o", "save_hist=0", "-o", "use_mouse=0",
         *(["-dump"] if dump else [])], markup.encode())


def github(url, dump, comments):
    if not shutil.which("gh"):
        raise ValueError("GitHub の表示には gh が必要です")
    parts = [part for part in urlparse(url).path.split("/") if part]
    if len(parts) < 2:
        raise ValueError("GitHub のリポジトリ URL を指定してください")
    repo = "/".join(parts[:2])
    if len(parts) >= 4 and parts[2] in ("issues", "pull") and parts[3].isdigit():
        kind = "issue" if parts[2] == "issues" else "pr"
        run(["gh", kind, "view", url, *(["--comments"] if comments else [])])
    elif len(parts) >= 5 and parts[2] == "blob":
        ref, path = parts[3], "/".join(parts[4:])
        endpoint = f"repos/{repo}/contents/{quote(path)}?ref={quote(ref)}"
        result = subprocess.run(["gh", "api", endpoint, "-H", "Accept: application/vnd.github.raw+json"],
                                capture_output=True)
        if result.returncode:
            sys.stderr.buffer.write(result.stderr)
            raise ValueError("GitHub のファイルを取得できませんでした")
        if dump:
            sys.stdout.buffer.write(result.stdout)
        elif shutil.which("glow") and path.lower().endswith((".md", ".markdown")):
            run(["glow", "-p", "-"], result.stdout)
        else:
            run(["less", "-R"], result.stdout)
    elif len(parts) == 2:
        run(["gh", "repo", "view", repo])
    else:
        raise ValueError("対応する GitHub URL はリポジトリ、Issue、PR、blob のファイルです")


def resolve_target(parts):
    """Expand short AtCoder targets while accepting full URLs unchanged."""
    if len(parts) == 1:
        target = parts[0]
        if target.startswith("https://"):
            return target
        if re.fullmatch(r"[a-zA-Z]", target):
            task = target.lower()
            return f"https://atcoder.jp/contests/dp/tasks/dp_{task}"
    elif len(parts) == 2:
        contest, task = parts
        if not re.fullmatch(r"[a-zA-Z]", task):
            raise ValueError("問題番号は a-z の一文字で指定してください")
        task = task.lower()
        if contest.lower() in ("dp", "edpc"):
            return f"https://atcoder.jp/contests/dp/tasks/dp_{task}"
        match = re.fullmatch(r"(?:abc)?(\d{1,3})", contest.lower())
        if match:
            number = match.group(1).zfill(3)
            return f"https://atcoder.jp/contests/abc{number}/tasks/abc{number}_{task}"
    raise ValueError("URL、'300 a'、'abc300 a'、'edpc a'、または 'a' を指定してください")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="+", help="URL または AtCoder の略記 (例: 300 a / edpc a / a)")
    parser.add_argument("--lang", choices=("ja", "en"), help="AtCoder の表示言語 (default: URL の lang、なければ ja)")
    parser.add_argument("-e", "--editorial", action="store_true", help="AtCoder の解説本文を開く")
    parser.add_argument("-E", "--editorials", action="store_true", help="AtCoder の解説一覧を開く")
    parser.add_argument("--dump", action="store_true", help="端末操作なしで標準出力へ表示")
    parser.add_argument("--comments", action="store_true", help="GitHub の Issue/PR コメントも表示")
    args = parser.parse_args()
    try:
        url = resolve_target(args.target)
    except ValueError as exc:
        parser.exit(2, f"webread: {exc}\n")
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        parser.error("https:// で始まる URL を指定してください")
    try:
        if parsed.hostname == "atcoder.jp":
            lang = args.lang or parse_qs(parsed.query).get("lang", ["ja"])[0]
            if lang not in ("ja", "en"):
                raise ValueError("AtCoder の言語は ja または en を指定してください")
            canonical = urlunparse(parsed._replace(query=f"lang={lang}", fragment=""))
            if re.fullmatch(r"/contests/[^/]+/tasks/[^/]+/?", parsed.path):
                if args.editorial or args.editorials:
                    view_editorial(canonical, lang, args.dump, args.editorials)
                else:
                    source, _ = fetch_page(canonical)
                    view_html(atcoder_html(source, canonical, lang), args.dump)
            elif re.fullmatch(r"/contests/[^/]+/editorial/\d+/?", parsed.path):
                source, final_url = fetch_page(canonical)
                view_html(document_html(source, final_url), args.dump)
            else:
                raise ValueError("AtCoder の問題または解説 URL を指定してください")
        elif parsed.hostname == "github.com":
            if args.editorial or args.editorials:
                raise ValueError("-e / -E は AtCoder 専用です")
            github(url, args.dump, args.comments)
        else:
            raise ValueError("対応サイトは atcoder.jp と github.com です")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"webread: {exc}\n")


if __name__ == "__main__":
    main()
