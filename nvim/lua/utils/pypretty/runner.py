"""Pretty output for Leader's `pr` (<leader>pr runs `python runner.py <script.py> [args...]`).

The script runs exactly as `python <script.py>` does (same `sys.argv`, `sys.path[0]`, `__file__`,
`__name__ == "__main__"` and exit code). Only how its values LOOK changes, Jupyter-style:

  - numpy arrays print as `array([[1, 2, 3, 4], ...])`, numbers colored (negatives red), outliers bold, with
    `shape`/`dtype` and `mean ± std · min…max · n` below;
  - pandas frames become a boxed table: index, header, a colored row of dtypes and missing counts per column, one
    cell per value (conditional red/blue backgrounds by magnitude), and a dim stats line per numeric column;
  - numeric Series get a sparkline column and a histogram with ranges; correlation matrices get a legend;
  - sympy expressions use sympy's unicode pretty printer when sympy is installed (no dependency is added);
  - lists, dicts, tuples and sets wrap with indentation; missing values are `∅` and infinities `∞`;
  - a crash shows a clean traceback (rich's, with locals with `--locals`), and the run ends with a dim timing badge.
  - `plt.show()` draws the figure in the pane with truecolor half blocks and reports the PNG path (`--no-plots` off).

Every run clears the terminal pane first (and its scrollback) so only the last result is on screen; `--no-clear`
leaves what was there. Everything is sized to the terminal: the pane's width, and a frame is cut at the pane's height (pandas adds
`...` and the shape still counts every row). Piped or redirected stdout is byte-identical: nothing is
patched when stdout is not a terminal. `NO_COLOR=1` turns the colors off, the layout stays.
"""
import builtins
import importlib.machinery
import math
import os
import re
import shutil
import sys
import textwrap
import time
import types
from html.parser import HTMLParser

RESET = "\x1b[0m"
DIM = "\x1b[2m"
BOLD = "\x1b[1m"
NUMBER_COLOR = "\x1b[36m"
NEGATIVE_COLOR = "\x1b[31m"
KEYWORD_COLOR = "\x1b[35m"

NUMBER = re.compile(r"(?<![\w.])-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?(?![\w.])")
KEYWORD = re.compile(r"\b(?:True|False|None|nan|NaN|inf|Inf|NaT)\b")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
CONTAINERS = (dict, list, tuple, set, frozenset)

_pretty_repr = None
_pretty_checked = False

# set from the command line: --light (theme), --locals (rich traceback), --no-conditional
LIGHT = False
SHOW_LOCALS = False
CONDITIONAL = True
CLEAR = True
PLOTS = True
STARTED = 0.0


def width():
    """The terminal width, leaving the last column free (a line that fills it wraps twice)."""
    try:
        return max(12, shutil.get_terminal_size((80, 24)).columns - 1)
    except Exception:
        return 79


def height():
    """The terminal's rows: how many lines a table may use before it stops being readable."""
    try:
        return max(12, shutil.get_terminal_size((80, 24)).lines)
    except Exception:
        return 24


def colors():
    """ANSI colors only on a real terminal, never with NO_COLOR (the standard opt-out)."""
    if os.environ.get("NO_COLOR") or os.environ.get("TERM") == "dumb":
        return False
    try:
        return sys.stdout.isatty()
    except Exception:
        return False


def paint(text, outlier=None):
    """Color values: numbers cyan (negatives red), outliers bold, booleans magenta, missing ∅, infinity ∞."""
    # text that already carries escapes (a library's own colors) is left alone: painting it would
    # rewrite the numbers inside "\x1b[31m"
    if "\x1b" in text:
        return text

    def number(match):
        token = match.group(0)
        shade = NEGATIVE_COLOR if token.startswith("-") else NUMBER_COLOR
        if outlier is not None:
            try:
                value = float(token)
            except ValueError:
                value = None
            if value is not None and outlier(value):
                return BOLD + shade + token + RESET
        return shade + token + RESET

    def keyword(match):
        token = match.group(0)
        low = token.lower()
        if low in ("none", "nan", "nat"):
            return KEYWORD_COLOR + "∅" + RESET
        if low == "inf":
            return NUMBER_COLOR + "∞" + RESET
        return KEYWORD_COLOR + token + RESET

    return KEYWORD.sub(keyword, NUMBER.sub(number, text))


def dim(text, color):
    return DIM + text + RESET if color else text


def bold(text, color):
    return BOLD + text + RESET if color else text


def _trim(value, columns):
    """A short stand-in for a huge container: first and last items, with the count in between."""
    limit = max(8, columns // 5)
    try:
        if isinstance(value, (list, tuple, set, frozenset)) and len(value) > limit:
            items = list(value)
            head, tail = items[: limit // 2], items[-(limit - limit // 2) :]
            middle = ["... +%d more" % (len(items) - limit)]
            if isinstance(value, list):
                return head + middle + tail
            return type(value)(head + middle + tail)
        if isinstance(value, dict) and len(value) > limit:
            items = list(value.items())
            head, tail = items[: limit // 2], items[-(limit - limit // 2) :]
            return dict(head + [("... +%d more" % (len(items) - limit), None)] + tail)
    except Exception:
        pass
    return value


def compact_container(value, columns):
    """One wrapped line instead of pprint's one item per line, even for a huge dict or list."""
    value = _trim(value, columns)
    limit = max(20, columns // 2)
    gap = lambda part: isinstance(part, str) and part.startswith("... +") and part.endswith(" more")

    def item(part):
        return part if gap(part) else repr(part) if len(repr(part)) <= limit else repr(part)[: limit - 3] + "..."

    if isinstance(value, dict):
        text = "{" + ", ".join(key if gap(key) else "%s: %s" % (item(key), item(val)) for key, val in value.items()) + "}"
    elif isinstance(value, (list, tuple, set, frozenset)):
        pair = {list: ("[", "]"), tuple: ("(", ")"), set: ("{", "}"), frozenset: ("frozenset({", "})")}[
            type(value)
        ]
        start, end = pair
        text = start + ", ".join(item(part) for part in value) + end
    else:
        return None
    return "\n".join(
        textwrap.wrap(
            text,
            width=max(8, columns - 1),
            break_long_words=False,
            break_on_hyphens=False,
            subsequent_indent=" ",
        )
        or [text]
    )


def rich_pretty():
    """rich's pretty printer when the project has it (loaded on the first container, never required)."""
    global _pretty_repr, _pretty_checked
    if not _pretty_checked:
        _pretty_checked = True
        try:
            from rich.pretty import pretty_repr

            _pretty_repr = pretty_repr
        except Exception:  # no rich: pprint is more than enough
            _pretty_repr = None
    return _pretty_repr


def _plain_container(value):
    """dict/list/tuple/set whose str() is its repr(): rich/pprint show the same text, only nicer."""
    return isinstance(value, CONTAINERS) and type(value).__str__ is object.__str__


# ── statistics, outliers and conditional colors ──────────────────────────────
def numbers(values):
    """The finite numbers in a sequence of displayed or real values."""
    out = []
    for value in values:
        try:
            number = float(value)
        except (TypeError, ValueError):
            continue
        if math.isfinite(number):
            out.append(number)
    return out


def summarise(values):
    """mean ± std, min…max and n — the little summary printed under numeric data."""
    values = numbers(values)
    if len(values) < 2:
        return None
    count = len(values)
    mean = sum(values) / count
    variance = sum((value - mean) ** 2 for value in values) / (count - 1 if count > 1 else 1)
    return {
        "n": count,
        "mean": mean,
        "std": math.sqrt(variance),
        "min": min(values),
        "max": max(values),
    }


def fit(text, width):
    """Keep a summary line inside the pane, even after the caller indents it under a prefix."""
    return text if len(text) <= width else text[: max(1, width - 1)] + "…"


def short(value):
    return format(value, ".4g")


def stats_line(stats, label=""):
    return "%s%s ± %s · %s…%s · n=%d" % (
        label + ": " if label else "",
        short(stats["mean"]),
        short(stats["std"]),
        short(stats["min"]),
        short(stats["max"]),
        stats["n"],
    )


def outlier(stats):
    """A test for values more than two standard deviations away from the mean."""
    if stats is None or stats["n"] < 3 or stats["std"] <= 0:
        return None
    mean, spread = stats["mean"], 2 * stats["std"]
    return lambda value: abs(value - mean) > spread


def histogram(values, width=24, bins=5):
    """A tiny text histogram with its ranges, for a numeric Series."""
    values = numbers(values)
    if len(values) < 4:
        return None
    low, high = min(values), max(values)
    if high <= low:
        return None
    counts = [0] * bins
    for value in values:
        counts[min(bins - 1, int((value - low) / (high - low) * bins))] += 1
    peak = max(counts)
    return [
        "%s–%s %s"
        % (
            short(low + (high - low) * at / bins).rjust(7),
            short(low + (high - low) * (at + 1) / bins).rjust(7),
            "█" * max(1, round(count / peak * width)) if count else "",
        )
        for at, count in enumerate(counts)
    ]


def dtype_style(name, color):
    """A type-colored dtype: blue integer, cyan float, green text, magenta bool, yellow date."""
    if not color:
        return name
    if name.startswith(("int", "uint")):
        shade = "\x1b[34m"
    elif name.startswith(("float", "complex")):
        shade = NUMBER_COLOR
    elif name.startswith("bool"):
        shade = KEYWORD_COLOR
    elif name.startswith(("str", "object", "category")):
        shade = "\x1b[32m"
    elif name.startswith(("datetime", "timedelta")):
        shade = "\x1b[33m"
    else:
        return dim(name, True)
    return shade + name + RESET


def conditional_style(value, biggest, light):
    """A background shade by magnitude: red below zero, blue above; theme-aware."""
    if biggest is None:
        return None
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(value):
        return None
    size = abs(value) / biggest
    if size < 0.15:
        return None
    strong = size >= 0.70
    if light:
        background = (217 if value < 0 else 153) if strong else (225 if value < 0 else 189)
        foreground = 0
    else:
        background = (88 if value < 0 else 26) if strong else (52 if value < 0 else 17)
        foreground = 255
    return "\x1b[48;5;%dm\x1b[38;5;%dm" % (background, foreground)


# ── pandas: a boxed table ────────────────────────────────────────────────────
class _Table(HTMLParser):
    """The cells of pandas' own HTML repr (`to_html`), so every formatted value comes from pandas."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows, self.dimensions = [], ""
        self.row = self.cell = self.dimensions_parts = None
        self.tag = None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        elif tag in ("td", "th"):
            self.cell, self.tag = [], tag
        elif tag == "p":
            self.dimensions_parts = []

    def handle_endtag(self, tag):
        if tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None
        elif tag in ("td", "th") and self.cell is not None:
            self.row.append((self.tag, "".join(self.cell).strip()))
            self.cell = None
        elif tag == "p" and self.dimensions_parts is not None:
            self.dimensions = "".join(self.dimensions_parts).strip()
            self.dimensions_parts = None

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)
        elif self.dimensions_parts is not None:
            self.dimensions_parts.append(data)


def _clean(text, max_width):
    """One line per cell (a newline inside a value would break the grid)."""
    text = " ".join(str(text).replace("\r", "\n").split("\n"))
    return text if len(text) <= max_width else text[: max_width - 3] + "..."


def _plural(dimensions):
    """pandas writes `1 rows x 1 columns`; keep its shape line but read it like a sentence."""
    return re.sub(r"\b1 (row|column)s\b", r"1 \1", dimensions)


def pandas_text(value, columns, color):
    """pandas' own text repr when a table does not fit: painted values, the footer dimmed."""
    text = str(value)
    if not color:
        return "\n".join(fit(line, columns) for line in text.splitlines())
    lines = text.splitlines()
    footer = []
    while lines and (
        re.fullmatch(r"\[\d+ rows x \d+ columns\]", lines[-1]) or re.match(r"^(Name|dtype|Length|Freq): ", lines[-1])
    ):
        footer.insert(0, _plural(lines.pop()))
    body = [paint(fit(line, columns)) for line in lines]
    return "\n".join(body + [dim(fit(line, columns), True) for line in footer])


SPARK = "▁▂▃▄▅▆▇█"


def _is_corr(value, pandas):
    """A correlation matrix: numeric, symmetric labels, every value in [-1, 1] and a diagonal of 1."""
    try:
        if not isinstance(value, pandas.DataFrame) or len(value.columns) < 2:
            return False
        if list(value.columns) != list(value.index):
            return False
        if not all(pandas.api.types.is_numeric_dtype(dtype) for dtype in value.dtypes):
            return False
        if value.abs().max().max() > 1 + 1e-9:
            return False
        return all(abs(float(v) - 1) < 1e-9 for v in value.to_numpy().diagonal() if v == v)
    except Exception:
        return False


def _short_dtype(dtype):
    name = str(dtype)
    if name.startswith("datetime64"):
        return "datetime"
    if name.startswith("timedelta64"):
        return "timedelta"
    return name


def _heat(text, color):
    """The foreground of a correlation cell: red below zero, blue above, dim near zero."""
    if not color:
        return None
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    if value != value:  # NaN keeps its magenta
        return None
    size = abs(value)
    if size < 0.05:
        return DIM
    if value > 0:
        return "\x1b[94m" if size >= 0.7 else "\x1b[34m"
    return "\x1b[91m" if size >= 0.7 else "\x1b[31m"


def _spark(values):
    """One bar per displayed value, scaled between the smallest and the largest."""
    known = [value for value in values if value is not None and value == value]
    if len(known) < 2 or min(known) == max(known):
        return None
    low, high = min(known), max(known)
    bars = []
    for value in values:
        if value is None or value != value:
            bars.append("·")
        else:
            bars.append(SPARK[int((value - low) / (high - low) * (len(SPARK) - 1))])
    return bars


def frame(value, columns, lines, color):
    """A DataFrame/Series as a boxed table, or None when a terminal table would not fit."""
    pandas = sys.modules["pandas"]
    series = isinstance(value, pandas.Series)
    table = value.to_frame() if series else value

    names = ["" if name is None else str(name) for name in value.index.names]
    if series:
        heads = ["" if value.name is None else str(value.name)]
    elif value.columns.nlevels > 1:
        heads = [" / ".join(str(part) for part in column) for column in value.columns]
    else:
        heads = [str(column) for column in value.columns]
    if not heads:
        return None
    labels = names + heads
    count = len(labels)
    # a wall of columns is not a table in a terminal: pandas' own text is better there
    if count > 200:
        return None

    limit = pandas.get_option("display.max_rows")
    if not isinstance(limit, int) or limit <= 0:
        limit = 60
    limit = max(10, min(limit, lines - 8))
    try:
        parser = _Table()
        parser.feed(table.to_html(max_rows=limit, max_cols=None, show_dimensions=not series, border=0))
    except Exception:
        return None
    body = [[text for _, text in row] for row in parser.rows if any(tag == "td" for tag, _ in row)]
    if series and not body:
        return None
    if any(len(row) != count for row in body):
        return None

    # A: dtype and missing values under the header (the Series says it in its footer already)
    info = [""] * count
    missing = 0
    try:
        nulls = table.isna().sum()
        missing = int(nulls.sum())
        if not series:
            for at in range(count - len(names)):
                total = int(nulls.iloc[at])
                info[len(names) + at] = _short_dtype(table.dtypes.iloc[at]) + (" ·%d" % total if total else "")
    except Exception:
        pass

    max_cell = pandas.get_option("display.max_colwidth")
    max_cell = max_cell if isinstance(max_cell, int) and max_cell > 0 else 50
    labels = [_clean(label, max_cell) for label in labels]
    body = [[_clean(cell, max_cell) for cell in row] for row in body]

    # 1: mean/std/min/max per displayed column, for the summary and the outliers
    stats, biggest = [None] * count, [None] * count
    for at in range(len(names), count):
        values = numbers(row[at] for row in body)
        stats[at] = summarise(values)
        biggest[at] = max((abs(value) for value in values), default=None)

    # B: a sparkline column for numeric Series
    spark_at = None
    if series and len(body) >= 2 and len(heads) == 1:
        try:
            bars = _spark([float(row[len(names)]) for row in body])
        except (TypeError, ValueError):
            bars = None
        if bars:
            labels.append("spark")
            info.append("")
            stats.append(None)
            biggest.append(None)
            body = [row + [bar] for row, bar in zip(body, bars)]
            count += 1
            spark_at = count - 1
    heat = _is_corr(value, pandas)

    def layout(selection):
        """The labels, the info row, the cells and the widths of the selected columns ('…' is the cut)."""
        picked = [labels[at] if isinstance(at, int) else "…" for at in selection]
        details = [info[at] if isinstance(at, int) else "" for at in selection]
        rows = [[row[at] if isinstance(at, int) else "…" for at in selection] for row in body]
        widths = [max(len(row[at]) for row in [picked, details] + rows) for at in range(len(selection))]
        return picked, details, rows, widths, sum(widths) + 3 * len(selection) + 1

    selection = list(range(count))
    picked, details, rows, widths, total = layout(selection)
    if total > columns:
        # too wide: keep the index, the columns that fit and the last one, like Jupyter's "…" columns
        spark_tail = [spark_at] if spark_at is not None else []
        keep, last = list(range(len(names))), count - 1 - len(spark_tail)
        if last < len(names):
            return None
        for at in range(len(names), last):
            if layout(keep + [at, "…", last] + spark_tail)[4] <= columns:
                keep.append(at)
        selection = keep + ["…", last] + spark_tail
        picked, details, rows, widths, total = layout(selection)
        if total > columns:
            return None

    def cell(text, at, header=False, index=False, detail=False, original=None):
        padded = text.rjust(widths[at])
        if header:
            shade = dim(padded, color) if at == spark_at else bold(padded, color)
            return " " + shade + " "
        if index:
            return " " + padded + " "
        if at == spark_at:
            return " " + (dim(padded, color) if text == "·" else NUMBER_COLOR + padded + RESET if color else padded) + " "
        if detail and text.strip():
            found = re.match(r"^(\S+)(.*)$", text)
            if found:
                spacing = " " * (widths[at] - len(text))
                dtype = dtype_style(found.group(1), color)
                tail = found.group(2)
                if tail.strip() and color:
                    tail = KEYWORD_COLOR + tail + RESET
                return " " + spacing + dtype + tail + " "
            return " " + dim(padded, color) + " "
        if text.strip() in ("...", "..", "…"):
            return " " + dim(padded, color) + " "
        if isinstance(original, int) and CONDITIONAL and color:
            shade = conditional_style(text, biggest[original], LIGHT)
            if shade:
                return " " + shade + padded + RESET + " "
        if heat:
            shade = _heat(text, color)
            if shade:
                return " " + shade + padded + RESET + " "
        test = outlier(stats[original]) if isinstance(original, int) else None
        return " " + (paint(padded, test) if color else padded) + " "

    def rule(left, middle, right):
        return dim(left + middle.join("─" * (w + 2) for w in widths) + right, color)

    bar = dim("│", color)
    out = [rule("╭", "┬", "╮")]
    if any(label.strip() for label in picked):
        out.append(bar + bar.join(cell(label, at, header=True) for at, label in enumerate(picked)) + bar)
        if any(detail.strip() for detail in details):
            out.append(bar + bar.join(cell(detail, at, detail=True) for at, detail in enumerate(details)) + bar)
        out.append(rule("├", "┼", "┤"))
    for row in rows:
        out.append(
            bar
            + bar.join(
                cell(text, at, index=at < len(names), original=selection[at]) for at, text in enumerate(row)
            )
            + bar
        )
    out.append(rule("╰", "┴", "╯"))
    footer = ("dtype: " + str(value.dtype)) if series else _plural(parser.dimensions)
    if missing:
        footer += " · %d missing" % missing
    if footer:
        out.append(dim(fit(footer, columns), color))
    if heat:
        out.append(dim(fit("-1 red · 0 dim · +1 blue", columns), color))

    # 1 + 2: the summary under the table and, for a numeric Series, its histogram
    if series:
        if len(names) < len(stats) and stats[len(names)]:
            line = fit(stats_line(stats[len(names)]), columns)
            out.append(dim(paint(line) if color else line, color))
            if len(names) < count:
                chart = histogram(
                    numbers(row[len(names)] for row in body), min(40, max(4, columns - 18))
                )
                if chart:
                    out += [dim(fit(line, columns), color) for line in chart]
    else:
        shown, total_numeric = 0, sum(1 for at in range(len(names), count) if stats[at])
        for at in range(len(names), count):
            if stats[at] and shown < 8:
                line = fit(stats_line(stats[at], labels[at]), columns)
                out.append(dim(paint(line) if color else line, color))
                shown += 1
        if total_numeric > shown:
            out.append(dim("… %d more numeric columns" % (total_numeric - shown), color))
    return "\n".join(out)


# ── numpy: Jupyter's repr ────────────────────────────────────────────────────
def array(value, available, lines, color):
    """`str(array)` is `[[1 2 3 4] ...]`; Jupyter shows `repr(array)`: `array([[1, 2, 3, 4], ...])`.

    A long array is cut by numpy's own threshold (first and last values, `...`) so it fits the pane; the
    shape and the statistics below still describe every value, not just the visible ones.
    """
    numpy = sys.modules["numpy"]
    try:
        threshold = numpy.get_printoptions().get("threshold", 1000)
        if value.ndim == 0:
            cap = None
        elif value.ndim == 1:
            cap = max(8, available // 3)
        else:
            cap = max(8, max(10, lines - 8) * (value.shape[-1] if value.shape[-1] else 1))
        if threshold and threshold > 0:
            cap = min(cap, threshold) if cap is not None else threshold
        line_width = max(8, available - 2)  # numpy's own indent plus the caller's prefix are added later
        if cap is not None and value.size > cap:
            with numpy.printoptions(threshold=cap):
                text = numpy.array_repr(value, max_line_width=line_width)
        else:
            text = numpy.array_repr(value, max_line_width=line_width)
    except Exception:
        text = repr(value)

    pieces = []
    if "shape=" not in text:
        pieces.append("shape=%s" % (value.shape,))
    if "dtype=" not in text:
        pieces.append(str(value.dtype))
    stats = None
    try:
        if numpy.issubdtype(value.dtype, numpy.number):
            finite = value[numpy.isfinite(value)]
            if finite.size > 1:
                stats = {
                    "n": int(finite.size),
                    "mean": float(finite.mean()),
                    "std": float(finite.std(ddof=1 if finite.size > 1 else 0)),
                    "min": float(finite.min()),
                    "max": float(finite.max()),
                }
                pieces.append(stats_line(stats))
    except Exception:
        pass
    footer = fit(" · ".join(pieces), available)
    if not color:
        return text + "\n" + footer
    # mark the shell (the call and its dtype) before painting, so the numbers inside stay intact
    text = text.replace("array(", "\x00array(\x01", 1)
    text = re.sub(r"(, dtype=[^)]*)(\)\s*$)", "\x00\\1\x01\\2", text)
    text = paint(text, outlier(stats))
    return text.replace("\x00", DIM).replace("\x01", RESET) + "\n" + dim(paint(footer), True)


def render(value, columns, lines, color):
    """The text `print` would write for one argument: same values, Jupyter-looking."""
    if isinstance(value, str):
        return value
    sympy = sys.modules.get("sympy")
    kinds = () if sympy is None else tuple(
        kind for kind in (getattr(sympy, "Basic", None), getattr(sympy, "MatrixBase", None)) if kind is not None
    )
    if kinds and isinstance(value, kinds):
        # formulas: sympy's own unicode pretty printer (√, ∑, stacked fractions), with numbers colored
        try:
            text = sympy.pretty(value, use_unicode=True)
        except Exception:
            text = str(value)
        return paint(text) if color else text
    pandas = sys.modules.get("pandas")
    if pandas is not None and isinstance(value, (pandas.DataFrame, pandas.Series)):
        table = frame(value, columns, lines, color)
        if table is not None:
            return table
        return pandas_text(value, columns, color)
    numpy = sys.modules.get("numpy")
    if numpy is not None and isinstance(value, numpy.ndarray):
        return array(value, columns, lines, color)
    if _plain_container(value):
        pretty = rich_pretty()
        text = None
        if pretty is not None and len(value) <= 12:
            try:
                text = pretty(value, max_width=columns)
            except Exception:
                pass
        if text is None:
            text = compact_container(value, columns)
            if text is None:
                text = str(value)
        text = "\n".join(fit(line, columns) for line in text.splitlines())
        return paint(text) if color else text
    text = str(value)
    return paint(text) if color else text


class Output:
    """Patches `print` for the script's stdout: same arguments, prettier values."""

    def __init__(self):
        self.stdout = sys.stdout
        self.columns = width()
        self.lines = height()
        self.color = colors()
        self.tuned = set()
        self.original = builtins.print

    def tune(self):
        """numpy/pandas reprs sized to the terminal, once and only over their defaults."""
        numpy = sys.modules.get("numpy")
        if numpy is not None and "numpy" not in self.tuned:
            self.tuned.add("numpy")
            try:
                if numpy.get_printoptions().get("linewidth") == 75:
                    numpy.set_printoptions(linewidth=self.columns)
            except Exception:
                pass
        pandas = sys.modules.get("pandas")
        if pandas is not None and "pandas" not in self.tuned:
            self.tuned.add("pandas")
            try:
                if pandas.get_option("display.width") is None:
                    pandas.set_option("display.width", self.columns)
            except Exception:
                pass

    def __call__(self, *args, sep=" ", end="\n", file=None, flush=False):
        target = sys.stdout if file is None else file
        if target is not self.stdout or not args:
            return self.original(*args, sep=sep, end=end, file=file, flush=flush)
        self.tune()
        separator = " " if sep is None else sep
        parts, column = [], 0
        for at, arg in enumerate(args):
            if at:
                parts.append(separator)
                column += len(separator)
            # a value after a prefix gets the room that is left, and its other lines line up under it
            text = render(arg, max(8, self.columns - column), self.lines, self.color)
            if "\n" in text and column:
                text = text.replace("\n", "\n" + " " * column)
            parts.append(text)
            column = len(ANSI.sub("", text.rsplit("\n", 1)[-1]))
        line = "".join(parts) + ("\n" if end is None else end)
        self.stdout.write(line)
        if flush:
            self.stdout.flush()


# ── matplotlib: show() inside the terminal ──────────────────────────────────
def plot_dir():
    """Where the PNGs of `plt.show()` live (outside the project, but easy to open)."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    path = os.path.join(base, "leader", "plots")
    try:
        os.makedirs(path, exist_ok=True)
        return path
    except Exception:
        return None


def render_image(path, columns, lines):
    """A PNG as quadrant blocks: two pixels per axis in each cell, foreground and background at 24 bits."""
    try:
        from PIL import Image

        with Image.open(path) as source:
            image = source.convert("RGBA")
        # transparent figures: composite onto the theme's background so the pane looks native
        background = (255, 255, 255) if LIGHT else (24, 24, 28)
        flat = Image.new("RGBA", image.size, background + (255,))
        if not LIGHT:  # matplotlib's black ink would vanish on a dark pane
            ink = image.load()
            for y in range(image.height):
                for x in range(image.width):
                    red, green, blue, alpha = ink[x, y]
                    if alpha > 32 and max(red, green, blue) < 60:
                        ink[x, y] = (220, 220, 220, alpha)
        flat.alpha_composite(image)
        image = flat.convert("RGB")
        width = max(8, min(columns, 100))
        height = max(1, min(max(4, lines - 6), int(image.height / image.width * width / 2)))
        image = image.resize((width * 2, height * 2), Image.LANCZOS)
        pixels = image.load()
        glyphs = {
            (0, 0, 0, 0): " ",
            (1, 1, 1, 1): "█",
            (1, 0, 0, 0): "▘",
            (0, 1, 0, 0): "▝",
            (0, 0, 1, 0): "▖",
            (0, 0, 0, 1): "▗",
            (1, 1, 0, 0): "▀",
            (0, 0, 1, 1): "▄",
            (1, 0, 1, 0): "▌",
            (0, 1, 0, 1): "▐",
            (1, 0, 0, 1): "▚",
            (0, 1, 1, 0): "▞",
            (1, 1, 1, 0): "▛",
            (1, 1, 0, 1): "▜",
            (1, 0, 1, 1): "▙",
            (0, 1, 1, 1): "▟",
        }
        escapes = {}

        def shade(color):
            if color not in escapes:
                escapes[color] = "\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm" % (color[0] + color[1])
            return escapes[color]

        def distance(left, right):
            return sum(abs(a - b) for a, b in zip(left, right))

        out = []
        for row in range(height):
            cells = []
            for column in range(width):
                quad = (
                    pixels[column * 2, row * 2],
                    pixels[column * 2 + 1, row * 2],
                    pixels[column * 2, row * 2 + 1],
                    pixels[column * 2 + 1, row * 2 + 1],
                )
                back = max(set(quad), key=lambda color: quad.count(color))
                front = max((color for color in quad if color != back), key=lambda color: distance(color, back), default=back)
                bits = tuple(1 if distance(color, front) < distance(color, back) else 0 for color in quad)
                cells.append(shade((front, back)) + glyphs[bits])
            out.append("".join(cells) + RESET)
        return "\n".join(out)
    except Exception:
        return None


def install_plots(pyplot, columns, lines):
    """Replace show(): draw the figures here instead of opening a window, and report the PNG path."""

    def show(*args, **kwargs):
        try:
            for number in list(pyplot.get_fignums()):
                figure = pyplot.figure(number)
                directory = plot_dir()
                if not directory:
                    continue
                path = os.path.join(directory, "fig-%s-%d.png" % (time.strftime("%Y%m%d-%H%M%S"), number))
                figure.savefig(path, bbox_inches="tight", transparent=True)
                art = render_image(path, columns - 1, lines)
                if art:
                    sys.stdout.write(art + "\n")
                sys.stdout.write(dim("→ " + path, True) + "\n")
                sys.stdout.flush()
            pyplot.close("all")
        except Exception as error:
            sys.stdout.write(dim("plot: %s" % error, True) + "\n")
            sys.stdout.flush()

    pyplot.show = show


def watch_plots(columns, lines):
    """Patch pyplot.show when the script imports it: no early matplotlib import, no backend conflict."""
    original_import = builtins.__import__

    def imp(name, globals=None, locals=None, fromlist=(), level=0):
        module = original_import(name, globals, locals, fromlist, level)
        if "matplotlib.pyplot" in sys.modules:
            builtins.__import__ = original_import
            install_plots(sys.modules["matplotlib.pyplot"], columns, lines)
        return module

    builtins.__import__ = imp


def badge(status):
    """The dim line after a run: how long it took and how it ended."""
    return dim("%s %.2fs · exit %d" % ("✓" if status == 0 else "✗", time.monotonic() - STARTED, status), True)


def clean_traceback():
    """Drop the runner's own frames from what the crash shows."""
    previous = sys.excepthook
    ours = {os.path.abspath(__file__), __file__}

    def hook(kind, value, tb):
        while tb is not None:
            name = tb.tb_frame.f_code.co_filename
            if name not in ours and os.path.abspath(name) not in ours:
                break
            tb = tb.tb_next
        # 3.14's default hook prints the exception's own traceback, not the one it receives
        try:
            value = value.with_traceback(tb)
        except Exception:
            pass
        previous(kind, value, tb)
        if sys.stderr.isatty():
            sys.stderr.write("\n" + badge(1) + "\n")

    sys.excepthook = hook


def rich_tracebacks(columns):
    """rich's traceback (locals only with --locals) when the project installed rich."""
    if not sys.stderr.isatty():
        return
    try:
        from rich.traceback import install
    except Exception:
        return
    install(show_locals=SHOW_LOCALS, width=columns, extra_lines=1, word_wrap=False)


def run(script):
    """Execute `script` as the main module, exactly as `python script.py` (same metadata and globals)."""
    module = types.ModuleType("__main__")
    module.__dict__.update(
        __file__=script,
        __loader__=importlib.machinery.SourceFileLoader("__main__", script),
        __package__=None,
        __spec__=None,
        __cached__=None,
        __builtins__=builtins,
    )
    sys.modules["__main__"] = module
    with open(script, "rb") as file:
        code = compile(file.read(), script, "exec", dont_inherit=True)
    exec(code, module.__dict__)


def main(argv):
    global LIGHT, SHOW_LOCALS, CONDITIONAL, CLEAR, PLOTS, STARTED
    args = [arg for arg in argv[1:] if not arg.startswith("--")]
    LIGHT = "--light" in argv
    SHOW_LOCALS = "--locals" in argv
    CONDITIONAL = "--no-conditional" not in argv
    CLEAR = "--no-clear" not in argv
    PLOTS = "--no-plots" not in argv
    if not args:
        sys.stderr.write(__doc__)
        return 2
    script = os.path.abspath(args[0])
    if not os.path.isfile(script):
        sys.stderr.write("runner: no such file: %s\n" % args[0])
        return 2

    columns, lines = width(), height()
    # Only a terminal gets the contrasts (colors, width, tables): a pipe or a file gets the script's own bytes
    if sys.stdout.isatty():
        if CLEAR:  # clear the pane (and its scrollback) so only this run's output is on screen
            sys.stdout.write("\x1b[2J\x1b[3J\x1b[H")
            sys.stdout.flush()
        builtins.print = Output()
        if PLOTS:
            watch_plots(columns, lines)
    if sys.stderr.isatty():
        rich_tracebacks(columns)
    clean_traceback()

    sys.argv = [script] + list(args[1:])
    sys.path[0] = os.path.dirname(script)
    STARTED = time.monotonic()
    try:
        run(script)
    except SystemExit as exc:
        status = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
        if sys.stderr.isatty():
            sys.stderr.write("\n" + badge(status) + "\n")
        raise
    if sys.stderr.isatty():  # an unhandled exception's badge is written by the hook, after the traceback
        sys.stderr.write("\n" + badge(0) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
