# Writes tuned values into lua/flora/tune.lua itself, as its defaults.
#
# Only settings whose value differs from the file's are touched, and only
# the text of each value is replaced, so comments, alignment and every
# other line stay as they are. Each setting is found by walking the `T`
# table constructor key by key, at brace depth zero of each table, skipping
# strings and comments. After writing, the file is read back through Lua
# (tools/tune_json.lua); if any value does not come back as written, the
# original file is restored and the call fails.
#
# As a script: python3 -I tools/bake_tune.py < values.json
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TINYTEX = os.path.expanduser("~/Library/TinyTeX/bin/universal-darwin/texlua")
# TinyTeX where it is installed, else texlua from PATH (TeX Live, CI).
TEXLUA = TINYTEX if os.path.exists(TINYTEX) else (shutil.which("texlua") or "texlua")
TUNE = os.path.join(ROOT, "lua", "flora", "tune.lua")


def read_tune(path):
    """The table tune.lua at `path` returns, without overrides, as JSON."""
    env = dict(os.environ, FLORA_TUNE="", FLORA_TUNE_FILE=path)
    # texlua runs scripts only from files, so the loader goes in a temp file.
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write("package.path = './lua/?.lua;' .. package.path\n"
                "package.preload['flora.tune'] = function() return dofile(os.getenv('FLORA_TUNE_FILE')) end\n"
                "dofile('tools/tune_json.lua')\n")
    try:
        out = subprocess.run([TEXLUA, f.name], cwd=ROOT, env=env,
                             capture_output=True, text=True, check=True)
    finally:
        os.remove(f.name)
    data = json.loads(out.stdout)
    data.pop("_doc", None)
    data.pop("_choices", None)
    data.pop("_bounds", None)
    return data


def _skip(text, i):
    """Index past a string or comment starting at i, or i if none starts."""
    if text.startswith("--", i):
        j = text.find("\n", i)
        return len(text) if j < 0 else j
    if text[i] in "\"'":
        q, j = text[i], i + 1
        while j < len(text) and text[j] != q:
            j += 2 if text[j] == "\\" else 1
        return j + 1
    return i


def _value_span(text, i, hi):
    """(start, end) of the expression starting at or after i, ending before
    the next ',' or '}' at its own depth zero."""
    while text[i].isspace():
        i += 1
    start, depth = i, 0
    while i < hi:
        j = _skip(text, i)
        if j != i:
            i = j
            continue
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        i += 1
    end = i
    while text[end - 1].isspace():
        end -= 1
    return start, end


KEY = re.compile(r"\[?\"?([A-Za-z_][A-Za-z0-9_]*)\"?\]?\s*=(?!=)")


def _find(text, lo, hi, key):
    """Value span of `key = ...` among the fields of the table body lo..hi."""
    i, depth = lo, 0
    while i < hi:
        j = _skip(text, i)
        if j != i:
            i = j
            continue
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif depth == 0:
            m = KEY.match(text, i)
            if m and m.group(1) == key and (i == lo or not (text[i - 1].isalnum() or text[i - 1] == "_")):
                return _value_span(text, m.end(), hi)
            if m:
                i = m.end()
                continue
        i += 1
    raise KeyError(key)


def _table_body(text, span):
    s, e = span
    if text[s] != "{" or text[e - 1] != "}":
        raise ValueError(f"not a table: {text[s:e][:40]!r}")
    return s + 1, e - 1


def _match(text, i):
    """Index just past the '}' matching the '{' at i."""
    depth = 0
    while i < len(text):
        j = _skip(text, i)
        if j != i:
            i = j
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces")


def locate(text, path):
    """Span of the value at dotted `path` inside `local T = { ... }`."""
    m = re.search(r"local T = \{", text)
    span = (m.end() - 1, _match(text, m.end() - 1))
    for key in path.split("."):
        lo, hi = _table_body(text, span)
        span = _find(text, lo, hi, key)
    return span


def _num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int) or (isinstance(v, float) and v.is_integer() and abs(v) < 1e9):
        return str(int(v))
    return f"{round(v, 4):.4f}".rstrip("0").rstrip(".")


def literal(v):
    """A JSON value as a Lua literal, in tune.lua's style."""
    if isinstance(v, (bool, int, float)):
        return _num(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{ " + ", ".join(literal(x) for x in v) + " }"
    order = sorted(v, key=lambda k: (k != "range", k))
    return "{ " + ", ".join(f"{k} = {literal(v[k])}" for k in order) + " }"


def _is_curve(v):
    return isinstance(v, dict) and "range" in v and ("points" in v or "weights" in v)


def changed_leaves(new, old, path=""):
    """Dotted paths whose values differ; curves and lists count as one value."""
    out = []
    for k, v in new.items():
        p = f"{path}.{k}" if path else k
        if k not in old:
            continue
        if isinstance(v, dict) and not _is_curve(v):
            out += changed_leaves(v, old[k], p)
        elif not _same(v, old[k]):
            out.append(p)
    return out


def _same(a, b):
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) < 5e-5
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_same(a[k], b[k]) for k in a)
    return a == b


def _get(d, path):
    for k in path.split("."):
        d = d[k]
    return d


def bake(values, path=TUNE):
    """Write `values` (the tune tree) into tune.lua at `path`; returns the
    dotted paths changed."""
    old = read_tune(path)
    paths = changed_leaves(values, old)
    if not paths:
        return []
    text = open(path).read()
    spans = [(locate(text, p), literal(_get(values, p))) for p in paths]
    for (s, e), lit in sorted(spans, reverse=True):
        text = text[:s] + lit + text[e:]
    original = open(path).read()
    with open(path, "w") as f:
        f.write(text)
    try:
        back = read_tune(path)
        bad = [p for p in paths if not _same(_get(back, p), _get(values, p))]
        if bad:
            raise ValueError("values did not read back: " + ", ".join(bad))
    except Exception:
        with open(path, "w") as f:
            f.write(original)
        raise
    return paths


if __name__ == "__main__":
    print(json.dumps(bake(json.load(sys.stdin))))
