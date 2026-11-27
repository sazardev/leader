#!/usr/bin/env python3
"""Tests for nvim/lua/utils/pypretty/runner.py (what <leader>pr runs): the pure helpers (colors, width,
Jupyter-style arrays and DataFrames) and the real command (argv, sys.path, __main__, exit codes,
byte-identical output when piped, and the colored output on a pseudo-terminal). Hermetic: temporary scripts, no
uv, no network; numpy/pandas renderers are tested when they are installed."""
import contextlib
import importlib.util
import io
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # importing the runner must not leave a __pycache__ inside the config

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNNER = os.path.join(ROOT, "nvim", "lua", "utils", "pypretty", "runner.py")

fails = 0


def check(name, got, want):
    global fails
    if got == want:
        print("ok   " + name)
    else:
        fails += 1
        print("FAIL " + name)
        print("  got:  %r" % (got,))
        print("  want: %r" % (want,))


def load():
    spec = importlib.util.spec_from_file_location("pypretty_runner", RUNNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def strip(text):
    """The visible text: drop the ANSI escapes (the terminal's own protocol, not the script's output)."""
    clean = ""
    i = 0
    while i < len(text):
        if text[i] == "\x1b" and text[i + 1 : i + 2] == "[":
            i += 2
            while i < len(text) and not ("@" <= text[i] <= "~"):
                i += 1
            i += 1
            continue
        clean += text[i]
        i += 1
    return clean


def run(python, script, *args):
    return subprocess.run([python, RUNNER, script] + list(args), capture_output=True, text=True)


def plain(python, script, *args):
    return subprocess.run([python, script] + list(args), capture_output=True, text=True)


def capture(runner, **kwargs):
    """The stdout of the patched print, as the script would see it on a terminal."""
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        out = runner.Output()
        if "color" in kwargs:
            out.color = kwargs["color"]
        out.columns = kwargs.get("columns", 80)
        out.lines = kwargs.get("lines", 24)
        out(*kwargs["args"], **kwargs.get("print", {}))
    return out, buffer.getvalue()


def main():
    runner = load()

    # ── pure helpers ─────────────────────────────────────────────────────────
    painted = runner.paint("value 42 and True and 1e-7")
    check("paint: numbers are cyan", "\x1b[36m42\x1b[0m" in painted, True)
    check("paint: keywords are magenta", "\x1b[35mTrue\x1b[0m" in painted, True)
    check("paint: only colors are added", strip(painted), "value 42 and True and 1e-7")
    check("paint: an escape already there is left alone", runner.paint("\x1b[31m42\x1b[0m"), "\x1b[31m42\x1b[0m")
    check("paint: identifiers keep their digits", runner.paint("column_7 = 7"), "column_7 = \x1b[36m7\x1b[0m")
    check("paint: negative numbers are red", runner.paint("-3.2"), "\x1b[31m-3.2\x1b[0m")
    check("paint: missing and infinity have symbols", strip(runner.paint("None nan inf True")), "∅ ∅ ∞ True")
    test = runner.outlier(runner.summarise([0] * 10 + [5]))
    check("paint: outliers are bold", runner.paint("5", test), "\x1b[1m\x1b[36m5\x1b[0m")
    check("paint: ordinary values are not bold", runner.paint("0.1", test), "\x1b[36m0.1\x1b[0m")

    stats = runner.summarise([1, 2, 3, 4])
    check("summarise: mean", stats["mean"], 2.5)
    check("summarise: n", stats["n"], 4)
    check("stats line", runner.stats_line(stats), "2.5 ± 1.291 · 1…4 · n=4")
    chart = runner.histogram([1, 1, 2, 8, 8, 8])
    check("histogram: five bands with bars", len(chart) == 5 and "█" in chart[-1], True)
    check("dtype: integers are blue", runner.dtype_style("int64", True), "\x1b[34mint64\x1b[0m")
    check("dtype: text is green", runner.dtype_style("str", True), "\x1b[32mstr\x1b[0m")
    check("conditional: dark blue background", runner.conditional_style(0.5, 1, False), "\x1b[48;5;17m\x1b[38;5;255m")
    check("conditional: light red background", runner.conditional_style(-0.9, 1, True), "\x1b[48;5;217m\x1b[38;5;0m")
    check("conditional: near zero has no background", runner.conditional_style(0.01, 1, False), None)
    runner.STARTED = time.monotonic() - 0.42
    badge = strip(runner.badge(0))
    check("badge: time and exit code", badge.startswith("✓ 0.4") and badge.endswith("exit 0"), True)

    # ── matplotlib: show() becomes a picture plus its path ───────────────────
    class Figure:
        def savefig(self, path, **kwargs):
            with open(path, "wb") as file:
                file.write(b"not a real png")

    class Pyplot:
        def get_fignums(self):
            return [1]

        def figure(self, number):
            return Figure()

        def close(self, what):
            pass

    old_cache = os.environ.get("XDG_CACHE_HOME")
    with tempfile.TemporaryDirectory() as cache:
        os.environ["XDG_CACHE_HOME"] = cache
        fake = Pyplot()
        runner.install_plots(fake, 60, 20)
        shown = io.StringIO()
        with contextlib.redirect_stdout(shown):
            fake.show()
        text = strip(shown.getvalue())
        check("plot: show() is replaced", callable(fake.show), True)
        check("plot: it reports the PNG path", text.startswith("→ ") and text.strip().endswith(".png"), True)
        check("plot: the PNG is in the plots folder", os.path.basename(os.path.dirname(text.strip())), "plots")
    if old_cache is None:
        del os.environ["XDG_CACHE_HOME"]
    else:
        os.environ["XDG_CACHE_HOME"] = old_cache

    try:
        from PIL import Image

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "test.png")
            image = Image.new("RGB", (20, 10), (255, 255, 255))
            for y in range(10):
                for x in range(10):
                    image.putpixel((x, y), (0, 0, 0) if (x + y) % 2 else (255, 255, 255))
            image.save(path)
            art = runner.render_image(path, 10, 6)
            blocks = "▀▄▌▐▚▞▖▗▘▙▛▜▝▟█"
            check("plot: quadrant glyphs with truecolor", "\x1b[38;2;" in art and any(ch in art for ch in blocks), True)
            check("plot: one line per two pixel rows", len(art.splitlines()), 2)

            ink = os.path.join(tmp, "ink.png")
            Image.new("RGBA", (20, 10), (0, 0, 0, 255)).save(ink)
            was_light = runner.LIGHT
            runner.LIGHT = False
            dark = runner.render_image(ink, 10, 6)
            runner.LIGHT = True
            light = runner.render_image(ink, 10, 6)
            runner.LIGHT = was_light
            check("plot: black ink is lifted on a dark pane", "38;2;220;220;220" in dark, True)
            check("plot: black ink stays black on a light pane", "38;2;0;0;0" in light, True)
    except ImportError:
        print("skip plot pixels: Pillow is not installed")

    check("render: a string is never touched", runner.render("42 and [bold]", 80, 24, True), "42 and [bold]")
    check("render: an int is colored", strip(runner.render(42, 80, 24, True)), "42")
    check("render: NO_COLOR keeps the text", runner.render(42, 80, 24, False), "42")
    check("render: a dict keeps its text", strip(runner.render({"a": 1, "b": [2, 3]}, 80, 24, True)), "{'a': 1, 'b': [2, 3]}")
    wrapped = strip(runner.render(list(range(40)), 40, 24, True))
    check("render: a long container wraps to the width", max(len(line) for line in wrapped.splitlines()) <= 40, True)
    huge = runner.render(list(range(1000)), 80, 24, False)
    check("render: a huge list is cut, not one item per line", "..." in huge and huge.count("\n") < 5, True)
    huge_dict = runner.render({f"k{i}": i for i in range(100)}, 80, 24, False)
    check("render: a huge dict is cut too", "..." in huge_dict and huge_dict.count("\n") < 5, True)

    try:
        import numpy

        text = strip(runner.render(numpy.array([[1, 2], [3, 4]]), 80, 24, True))
        check("numpy: Jupyter's repr, one row per line", text.splitlines()[0], "array([[1, 2],")
        shape = next((line for line in text.splitlines() if line.startswith("shape=")), None)
        check("numpy: shape, dtype and stats in one line", shape.startswith("shape=(2, 2) · int64") and "n=4" in shape, True)
        summary = strip(runner.render(numpy.array([1.1, 1.2, 9.4, 1.0, 1.3]), 80, 24, True))
        check("numpy: mean ± std below the array", "±" in summary and "n=5" in summary, True)
        long = strip(runner.render(numpy.arange(60), 80, 24, True))
        check("numpy: a long array is cut with ...", "..." in long.splitlines()[0], True)
        check("numpy: the stats still count every value", "n=60" in long, True)
        narrow = strip(runner.render(numpy.arange(200).reshape(10, 20), 40, 12, True))
        check("numpy: a 2D array fits 40 columns", all(len(line) <= 40 for line in narrow.splitlines()), True)
        for columns in (25, 40, 60, 100, 160):
            for value in (numpy.arange(200), numpy.arange(200).reshape(10, 20)):
                rendered = strip(runner.render(value, columns, 12, True))
                check(
                    "matrix: %d columns, ndarray %dD" % (columns, value.ndim),
                    all(len(line) <= columns for line in rendered.splitlines()),
                    True,
                )
        check("numpy: the shell is dimmed", "\x1b[2marray(" in runner.render(numpy.array([1, 2]), 80, 24, True), True)
        check(
            "numpy: the dtype is dimmed",
            "dtype=int8\x1b[0m" in runner.render(numpy.array([1], dtype=numpy.int8), 80, 24, True),
            True,
        )
    except ImportError:
        print("skip numpy: it is not installed")

    try:
        import pandas

        table = strip(runner.render(pandas.DataFrame({"a": [1, 2], "b": [3.5, 4.5]}), 80, 24, True))
        lines = table.splitlines()
        check("frame: boxed", lines[0].startswith("╭") and any(line.startswith("╰") for line in lines), True)
        check("frame: the header has the columns", "a" in lines[1] and "b" in lines[1], True)
        check("frame: the shape", "2 rows × 2 columns" in lines, True)
        check("frame: the index is a column", any("│ 0 │" in line and "3.5" in line for line in lines), True)
        check("frame: dtypes under the header", "int64" in lines[2] and "float64" in lines[2], True)
        missing = strip(runner.render(pandas.DataFrame({"a": [1.0, None]}), 80, 24, True))
        check("frame: missing values, by column and in the footer", "·1" in missing and "1 missing" in missing, True)
        series = strip(runner.render(pandas.Series([1, 2], name="x"), 80, 24, True))
        check("series: the name is the header and the dtype the footer", " x " in series and "dtype: int64" in series.splitlines(), True)
        spark = strip(runner.render(pandas.Series([1, 4, 2, 8], name="x"), 80, 24, True))
        check("series: a sparkline column", "spark" in spark and any(bar in spark for bar in runner.SPARK), True)
        corr = runner.render(pandas.DataFrame({"a": [1.0, -0.8], "b": [-0.8, 1.0]}).corr().round(2), 80, 24, True)
        check("corr: a heatmap legend", "-1 red · 0 dim · +1 blue" in strip(corr), True)
        check("corr: blue for positive, red for negative", "\x1b[48;5;26m" in corr and "\x1b[48;5;88m" in corr, True)
        check("corr: a normal frame is not a heatmap", runner._is_corr(pandas.DataFrame({"a": [1, 2], "b": [3, 4]}), pandas), False)
        check("frame: a stats line per numeric column", "a: 0.8333 ± 2.754 · -2…3.5 · n=3" in strip(runner.render(pandas.DataFrame({"a": [1.0, -2.0, 3.5, None]}), 80, 24, True)), True)
        check("frame: dtypes are colored", "\x1b[36mfloat64\x1b[0m" in runner.render(pandas.DataFrame({"a": [1.0, 2.0]}), 80, 24, True), True)
        check("frame: cells have a conditional background", "\x1b[48;5;" in runner.render(pandas.DataFrame({"a": [1.0, -2.0, 3.5]}), 80, 24, True), True)
        was = runner.CONDITIONAL
        runner.CONDITIONAL = False
        check("frame: the flag can turn the background off", "\x1b[48;5;" in runner.render(pandas.DataFrame({"a": [1.0, -2.0, 3.5]}), 80, 24, True), False)
        runner.CONDITIONAL = was
        series_stats = strip(runner.render(pandas.Series([1, 4, 2, 8, 3, 7, 1.5, 6], name="temp"), 80, 24, True))
        check("series: summary and histogram", "±" in series_stats and "█" in series_stats and "–" in series_stats, True)
        wide = strip(runner.render(pandas.DataFrame({f"c{i}": [1] for i in range(40)}), 80, 24, True))
        check("frame: too many columns are cut with …", " … " in wide, True)
        big = strip(runner.render(pandas.DataFrame({"a": range(100)}), 80, 24, True))
        check("frame: the rows stop at the pane and say how many there are", "100 rows × 1 column" in big and "..." in big, True)
        check("frame: NO_COLOR keeps the box", "╭" in runner.render(pandas.DataFrame({"a": [1]}), 80, 24, False), True)
        check("frame: NO_COLOR leaves the stats plain", "\x1b[" not in runner.render(pandas.DataFrame({"a": [1, 2, 3]}), 80, 24, False), True)
        narrow = strip(runner.render(pandas.DataFrame({"a": [1.0, -2.0], "b": [3.5, 4.5]}), 40, 12, True))
        check("frame: a 40-column pane stays inside the pane", all(len(line) <= 40 for line in narrow.splitlines()), True)
        narrow_series = strip(runner.render(pandas.Series([1, 4, 2, 8, 3, 7, 1.5, 6], name="temp"), 40, 12, True))
        check("series: the histogram fits 40 columns", all(len(line) <= 40 for line in narrow_series.splitlines()), True)
        for columns in (25, 40, 60, 100, 160):
            for value in (
                pandas.DataFrame({"a": [1, -2, 3], "b": [3.5, 4.5, None]}),
                pandas.DataFrame({f"c{i}": range(4) for i in range(20)}),
                pandas.Series([1, 4, 2, 8, 3, 7, 1.5, 6], name="t"),
                pandas.DataFrame({"x": [1.0, 0.4, -0.2], "y": [0.4, 1.0, -0.8], "z": [-0.2, -0.8, 1.0]}).corr(),
            ):
                rendered = strip(runner.render(value, columns, 12, True))
                check(
                    "matrix: %d columns, %s" % (columns, type(value).__name__),
                    all(len(line) <= columns for line in rendered.splitlines()),
                    True,
                )
        check("frame: too narrow falls back to pandas' text", "╭" in strip(runner.render(pandas.DataFrame({"a": [1]}), 8, 24, True)), False)
        check("frame: the shape line reads like a sentence", runner._plural("1 rows x 1 columns"), "1 row x 1 column")
    except ImportError:
        print("skip pandas: it is not installed")

    try:
        import sympy

        formula = strip(runner.render(sympy.sqrt(sympy.Symbol("x") ** 2 + 1), 80, 24, True))
        check("sympy: unicode formulas", "╲╱" in formula, True)
        matrix = strip(runner.render(sympy.Matrix([[1, 2], [3, 4]]), 80, 24, True))
        check("sympy: a pretty matrix", "⎡" in matrix and "⎦" in matrix, True)
    except ImportError:
        print("skip sympy: it is not installed")

    old_columns = os.environ.get("COLUMNS")
    os.environ["COLUMNS"] = "120"
    check("width: COLUMNS, less the last column", runner.width(), 119)
    if old_columns is None:
        del os.environ["COLUMNS"]
    else:
        os.environ["COLUMNS"] = old_columns

    # ── print: the same arguments, prettier values ───────────────────────────
    _, text = capture(runner, color=True, args=(42, "plain 42", {"a": 1}), print={"sep": "|", "end": "!"})
    check("print: joins with sep and ends with end", text.endswith("!"), True)
    check("print: values are colored", "\x1b[36m42\x1b[0m" in text, True)
    check("print: the containers are colored too", "'a': \x1b[36m1\x1b[0m" in text, True)
    check("print: a string keeps its text and its bytes", "plain 42" in text and "\x1b[36mplain" not in text, True)

    _, text = capture(runner, color=True, args=("x:", list(range(30))), columns=30)
    check("print: the extra lines line up under the value", all(line.startswith("   ") for line in text.splitlines()[1:]), True)

    old_no_color = os.environ.get("NO_COLOR")
    os.environ["NO_COLOR"] = "1"
    _, text = capture(runner, args=(42, "plain"), print={"sep": "|"})
    check("print: NO_COLOR keeps the formatting, drops the colors", text, "42|plain\n")
    if old_no_color is None:
        del os.environ["NO_COLOR"]
    else:
        os.environ["NO_COLOR"] = old_no_color

    # ── the real command: same python file.py ────────────────────────────────
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "sibling.py"), "w") as file:
            file.write("VALUE = 42\n")
        script = os.path.join(tmp, "probe.py")
        with open(script, "w") as file:
            file.write(
                "import os, sys\n"
                "import sibling\n"
                "print('argv', sys.argv)\n"
                "print('name', __name__)\n"
                "print('file', os.path.basename(__file__))\n"
                "print('path0', os.path.basename(sys.path[0]))\n"
                "print('sibling', sibling.VALUE)\n"
            )
        python = sys.executable
        got, want = run(python, script, "one", "two"), plain(python, script, "one", "two")
        check("run: exit code", got.returncode, 0)
        check("run: argv, __main__, __file__, sys.path[0], a sibling import", got.stdout, want.stdout)
        check("run: piped output is byte-identical", got.stderr, want.stderr)

        data = os.path.join(tmp, "data.py")
        with open(data, "w") as file:
            file.write("print('list', list(range(40)))\nprint('dict', {'a': 1, 'b': 2})\n")
        check("pipe: a container is not reformatted", run(python, data).stdout, plain(python, data).stdout)

        boom = os.path.join(tmp, "boom.py")
        with open(boom, "w") as file:
            file.write("raise RuntimeError('boom')\n")
        got, want = run(python, boom), plain(python, boom)
        check("crash: exit code 1", got.returncode, 1)
        check("crash: the piped traceback still names the error", "RuntimeError: boom" in got.stderr, True)
        check("crash: the piped traceback drops the runner frames", "runner.py" in got.stderr, False)

        code = os.path.join(tmp, "code.py")
        with open(code, "w") as file:
            file.write("import sys\nsys.exit(3)\n")
        check("run: sys.exit(3) is 3", run(python, code).returncode, 3)
        check("run: a missing script is an error", run(python, os.path.join(tmp, "nope.py")).returncode, 2)

        # ── a terminal: colors, the width and a clean traceback ──────────────
        if shutil.which("script") and sys.platform.startswith("linux"):
            command = ["script", "-qec", "", "/dev/null"]

            def on_tty(target, columns=100, flags=()):
                env = os.environ.copy()
                env["COLUMNS"] = str(columns)
                command[2] = " ".join(shlex.quote(part) for part in [sys.executable, RUNNER, *flags, target])
                return subprocess.run(command, capture_output=True, text=True, env=env).stdout.replace("\r", "")

            values = os.path.join(tmp, "values.py")
            with open(values, "w") as file:
                file.write("print('v', 1, 2.5, True)\n")
            colored = on_tty(values)
            check("tty: the pane is cleared before the run", colored.startswith("\x1b[2J\x1b[3J\x1b[H"), True)
            check("tty: numbers are colored", "\x1b[36m" in colored, True)
            visible = "\n".join(line for line in strip(colored).splitlines() if "exit " not in line).strip()
            check("tty: the text is the same", visible, plain(python, values).stdout.strip())
            check("tty: a badge closes a successful run", "✓" in strip(colored) and "exit 0" in strip(colored), True)
            check("tty: --no-clear keeps the previous output", on_tty(values, 100, ["--no-clear"]).startswith("\x1b["), False)

            crashed = on_tty(boom)
            check("tty: the traceback has no runner frames", "runner.py" in crashed, False)
            check("tty: the traceback names the script", "boom.py" in crashed, True)
            check("tty: the error is there", "boom" in strip(crashed), True)
            check("tty: a badge closes a failed run", "✗" in strip(crashed) and "exit 1" in strip(crashed), True)

            try:
                import pandas  # noqa: F401

                conditional = os.path.join(tmp, "conditional.py")
                with open(conditional, "w") as file:
                    file.write("import pandas as pd\nprint(pd.DataFrame({'a': [1.0, -2.0, 3.5]}))\n")
                light = on_tty(conditional, 100, ["--light"])
                check("tty: --light uses the light palette", "\x1b[48;5;189m" in light, True)
            except ImportError:
                print("skip tty: pandas is not installed")

            wide = os.path.join(tmp, "wide.py")
            with open(wide, "w") as file:
                file.write("import numpy as np\nprint(np.arange(33) * 1000000)\n")
            try:
                import numpy  # noqa: F401

                lines = strip(on_tty(wide, 100)).splitlines()
                check("tty: numpy uses the terminal width", all(len(line) <= 99 for line in lines), True)
                check("tty: numpy fits more than the default 75 columns", max(len(line) for line in lines) > 75, True)
            except ImportError:
                print("skip tty: numpy is not installed")
        else:
            print("skip tty: no `script` to open a pseudo-terminal")

    print("\nALL OK" if fails == 0 else "\nFAILURES: %d" % fails)
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
