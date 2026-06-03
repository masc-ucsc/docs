"""MkDocs custom fence formatter for Pyrope code blocks."""

from __future__ import annotations

import html
import os
import re
import subprocess
import tempfile
from pathlib import Path


_LINE_RE = re.compile(r"<td class=line>(.*?)</td>", re.DOTALL)


def _docs_root() -> Path:
    return Path(__file__).resolve().parent


def _grammar_path() -> Path | None:
    env_path = os.environ.get("PYROPE_TREE_SITTER_GRAMMAR")
    candidates = [
        Path(env_path) if env_path else None,
        _docs_root() / "tree-sitter-pyrope",
        _docs_root().parent / "tree-sitter-pyrope",
    ]

    for candidate in candidates:
        if candidate and (candidate / "tree-sitter.json").is_file():
            return candidate
    return None


def _tree_sitter_cli(grammar: Path) -> str:
    env_cli = os.environ.get("PYROPE_TREE_SITTER_CLI")
    if env_cli:
        return env_cli

    local_cli = grammar / "node_modules" / ".bin" / "tree-sitter"
    if local_cli.is_file():
        return str(local_cli)

    return "tree-sitter"


def _highlight(source: str) -> str | None:
    grammar = _grammar_path()
    if grammar is None:
        return None

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".prp",
        encoding="utf-8",
        delete=False,
    ) as tmp:
        tmp.write(source)
        tmp_path = Path(tmp.name)

    try:
        result = subprocess.run(
            [
                _tree_sitter_cli(grammar),
                "highlight",
                "--html",
                "--css-classes",
                "-p",
                str(grammar),
                str(tmp_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"Pyrope highlighting disabled: {exc}")
        return None
    finally:
        tmp_path.unlink(missing_ok=True)

    lines = _LINE_RE.findall(result.stdout)
    if not lines:
        return None

    return "".join(lines)


def _plain_code(source: str) -> str:
    return html.escape(source)


def fence_pyrope(source, language, class_name, options, md, **kwargs):
    """Render a ```pyrope fenced block using tree-sitter-pyrope highlights."""

    classes = kwargs.get("classes", [])
    attrs = kwargs.get("attrs", {})
    id_value = kwargs.get("id_value", "")

    code = _highlight(source)
    if code is None:
        code = _plain_code(source)

    class_values = ["highlight", "pyrope-highlight"]
    if class_name:
        class_values.append(class_name)
    class_values.extend(classes)

    id_attr = f' id="{html.escape(id_value, quote=True)}"' if id_value else ""
    class_attr = f' class="{" ".join(html.escape(c, quote=True) for c in class_values)}"'
    extra_attrs = "".join(
        f' {html.escape(str(k), quote=True)}="{html.escape(str(v), quote=True)}"'
        for k, v in attrs.items()
    )

    return f"<div{class_attr}{id_attr}{extra_attrs}><pre><code>{code}</code></pre></div>"
