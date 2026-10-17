import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("webread", ROOT / "scripts/webread.py")
webread = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = webread
spec.loader.exec_module(webread)


SAMPLE = """<html><head><title>A - Addition - AtCoder</title></head><body>
<header>Navigation</header><div id="task-statement"><span class="lang">
<span class="lang-ja"><div class="part"><section><h3>問題文</h3>
<p>整数 \\(A_i\\) は \\(1 \\le A_i \\le 9\\) です。</p>
<p><script type="math/tex">\\frac{1}{2}</script></p>
<h3>入力例 1</h3><pre>1 2\n3 4</pre></section></div>
<div class="part"><section><h3>入力</h3><pre>A_1 A_2 \\vdots A_{N-1}</pre></section></div></span>
<span class="lang-en" style="display:none"><h3>Problem Statement</h3><p>English text</p></span>
</span></div><footer>Footer</footer></body></html>"""


class WebreadTests(unittest.TestCase):
    def test_atcoder_selects_one_language_and_keeps_math_and_samples(self):
        rendered = webread.atcoder_html(SAMPLE, "https://atcoder.jp/contests/abc300/tasks/abc300_a", "ja")
        self.assertIn("問題文", rendered)
        self.assertIn("Aᵢ", rendered)
        self.assertIn("1 ≤ Aᵢ ≤ 9", rendered)
        self.assertIn("(1)/(2)", rendered)
        self.assertIn("A₁ A₂ ⋮ A[N-1]", rendered)
        self.assertIn("1 2\n3 4", rendered)
        self.assertNotIn("English text", rendered)
        self.assertNotIn("Navigation", rendered)
        self.assertNotIn("Footer", rendered)
        english = webread.atcoder_html(SAMPLE, "https://atcoder.jp/contests/abc300/tasks/abc300_a", "en")
        self.assertIn("English text", english)
        self.assertNotIn("問題文", english)
        self.assertNotIn("display:none", english)

    def test_atcoder_dollar_and_bare_tex_are_readable(self):
        source = """<title>C - Cross - AtCoder</title><div id="task-statement">
        <span class="lang-ja"><p>$1, 2, \\dots, N-1$ と $A_i, B_i$ を使う。</p>
        <p>A_i と B_i も表示する。A_{N-1}, \\vdots, /vdots</p>
        <pre>A_i \\dots</pre></span></div>"""
        rendered = webread.atcoder_html(source, "https://atcoder.jp/contests/abc300/tasks/abc300_c", "ja")
        self.assertIn("1, 2, …, N-1", rendered)
        self.assertIn("Aᵢ, Bᵢ", rendered)
        self.assertIn("A[N-1], ⋮, ⋮", rendered)
        self.assertIn("<pre>A_i \\dots</pre>", rendered)
        self.assertNotIn("$", rendered)

    def test_atcoder_short_targets(self):
        cases = {
            ("300", "c"): "https://atcoder.jp/contests/abc300/tasks/abc300_c",
            ("abc7", "A"): "https://atcoder.jp/contests/abc007/tasks/abc007_a",
            ("edpc", "a"): "https://atcoder.jp/contests/dp/tasks/dp_a",
            ("dp", "z"): "https://atcoder.jp/contests/dp/tasks/dp_z",
            ("A",): "https://atcoder.jp/contests/dp/tasks/dp_a",
        }
        for parts, expected in cases.items():
            with self.subTest(parts=parts):
                self.assertEqual(webread.resolve_target(parts), expected)
        with self.assertRaises(ValueError):
            webread.resolve_target(("edpc", "ex"))

    def test_editorial_picks_task_article_and_skips_overall_links(self):
        listing = """<div id="main-container"><h2>A - Sample</h2><ul>
        <li>ユーザ解説 <a href="/contests/abc300/editorial/100">解説</a> by user</li>
        <li>公式 <a href="/contests/abc300/editorial/200">解説</a> by author</li>
        </ul><h3>コンテスト全体の解説</h3><ul>
        <li>公式 <a href="/contests/abc300/editorial/300">全体解説</a></li>
        </ul></div>"""
        url = "https://atcoder.jp/contests/abc300/tasks/abc300_a/editorial?lang=ja"
        links = webread.editorial_links(listing, url)
        self.assertEqual([entry[0] for entry in links], [
            "https://atcoder.jp/contests/abc300/editorial/100",
            "https://atcoder.jp/contests/abc300/editorial/200",
        ])
        with patch.object(webread, "fetch_page", side_effect=[
            (listing, url),
            ("<title>解説</title><header>Navigation</header><div id='main-container'><p>本文 $A_i$</p></div><footer>Footer</footer>",
             "https://atcoder.jp/contests/abc300/editorial/200"),
        ]) as fetch, patch.object(webread, "view_html") as view:
            webread.view_editorial("https://atcoder.jp/contests/abc300/tasks/abc300_a?lang=ja", "ja", False, False)
        self.assertEqual(fetch.call_args_list[0].args[0], url)
        self.assertIn("本文", view.call_args.args[0])
        self.assertIn("Aᵢ", view.call_args.args[0])
        self.assertNotIn("Navigation", view.call_args.args[0])
        self.assertNotIn("Footer", view.call_args.args[0])

    def test_edpc_external_editorial_link_is_retained(self):
        listing = """<div id="main-container"><ul>
        <li>ユーザ解説 <a href="/jump?url=https%3A%2F%2Fqiita.com%2Fuser%2Fitems%2F123">解説</a> by user</li>
        </ul><h3>コンテスト全体の解説</h3></div>"""
        links = webread.editorial_links(listing, "https://atcoder.jp/contests/dp/tasks/dp_a/editorial?lang=ja")
        self.assertEqual(links[0][0], "https://qiita.com/user/items/123")

    def test_editorial_short_option_routes_to_article(self):
        with patch.object(sys, "argv", ["webread", "-e", "300", "a"]), patch.object(webread, "view_editorial") as view:
            webread.main()
        self.assertEqual(view.call_args.args,
                         ("https://atcoder.jp/contests/abc300/tasks/abc300_a?lang=ja", "ja", False, False))

    def test_github_issue_and_repo_use_gh(self):
        with patch.object(webread, "run") as run:
            webread.github("https://github.com/cli/cli/issues/42", False, True)
            webread.github("https://github.com/cli/cli", False, False)
        self.assertEqual(run.call_args_list[0].args[0],
                         ["gh", "issue", "view", "https://github.com/cli/cli/issues/42", "--comments"])
        self.assertEqual(run.call_args_list[1].args[0], ["gh", "repo", "view", "cli/cli"])


if __name__ == "__main__":
    unittest.main()
