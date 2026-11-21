//! The documentation carried inside the `leader` binary (`leader docs`), so installing the app stays clean.
//!
//! The bytes come from `scripts/docs-bundle.txt`, compressed by `build.rs` into OUT_DIR; this module only decompresses
//! and writes them. `leader docs` extracts to the user's data dir and opens the offline guide; installers that want the
//! files on disk use `--extract-to`, and `--extras` (on install.sh) is the opt-in, non-default way to ask for them.
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

use flate2::read::DeflateDecoder;

include!(concat!(env!("OUT_DIR"), "/docs_data.rs"));

fn say(line: &str) {
    // A piped `leader docs --list | head` must not panic on a closed stdout.
    use std::io::Write;
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{line}");
}

const GUIDE: &str = "docs/offline.html";
const HELP: &str = "leader docs — the offline documentation embedded in this binary

usage: leader docs [OPTIONS]

  (no options)      extract to ~/.local/share/leader/docs/VERSION and open the guide
  --path            print that directory, without extracting
  --extract-to DIR  extract there instead (used by `install.sh --extras`)
  --list            list the embedded files
  -h, --help        this help

The pack contains the generated guide, the standalone offline HTML, the cheat sheets and the Markdown sources.";

fn compressed(path: &str) -> Option<&'static [u8]> {
    DOCS.iter().find(|(name, _)| *name == path).map(|(_, data)| *data)
}

fn read(path: &str) -> io::Result<Vec<u8>> {
    let Some(bytes) = compressed(path) else {
        return Err(io::Error::new(io::ErrorKind::NotFound, path));
    };
    let mut out = Vec::new();
    DeflateDecoder::new(bytes).read_to_end(&mut out)?;
    Ok(out)
}

fn default_dir() -> PathBuf {
    let base = env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("leader/docs").join(env!("CARGO_PKG_VERSION"))
}

fn extract_to(dir: &Path) -> io::Result<usize> {
    fs::create_dir_all(dir)?;
    for &(rel, _) in DOCS {
        let dest = dir.join(rel);
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(dest, read(rel)?)?;
    }
    Ok(DOCS.len())
}

fn open(path: &Path) {
    // A browser is optional: a machine without xdg-open still has the extracted files, printed below.
    let _ =
        std::process::Command::new("xdg-open").arg(path).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).spawn();
}

fn esay(line: &str) {
    use std::io::Write;
    let mut out = io::stderr().lock();
    let _ = writeln!(out, "{line}");
}

/// `leader docs …`: extract, list or point at the embedded documentation.
pub fn run(args: &[OsString]) {
    let args: Vec<String> = args.iter().map(|a| a.to_string_lossy().into_owned()).collect();
    let mut extract = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => return say(HELP),
            "--list" => {
                for (path, _) in DOCS {
                    say(path);
                }
                return;
            }
            "--path" => return say(&default_dir().display().to_string()),
            "--extract-to" => {
                let Some(dir) = args.get(i + 1) else {
                    esay("leader docs: --extract-to needs a directory");
                    std::process::exit(2);
                };
                extract = Some(PathBuf::from(dir));
                i += 1;
            }
            arg if arg.starts_with("--extract-to=") => {
                extract = Some(PathBuf::from(&arg["--extract-to=".len()..]));
            }
            arg => {
                esay(&format!("leader docs: unknown option {arg} (use --help)"));
                std::process::exit(2);
            }
        }
        i += 1;
    }

    let automatic = extract.is_none();
    let dir = extract.unwrap_or_else(default_dir);
    match extract_to(&dir) {
        Ok(n) => {
            if automatic {
                open(&dir.join(GUIDE));
            }
            say(&format!("leader docs: {n} files in {}", dir.display()));
            if automatic {
                say(&format!("leader docs: opening {}", dir.join(GUIDE).display()));
            }
        }
        Err(e) => {
            esay(&format!("leader docs: cannot write {}: {e}", dir.display()));
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_docs_are_embedded() {
        assert!(!DOCS.is_empty(), "the binary must carry the documentation");
        assert!(compressed(GUIDE).is_some(), "the offline guide is part of the pack");
        assert!(compressed("docs/cheatsheets/python.md").is_some());
        assert!(DOCS.iter().all(|(path, _)| !path.contains("..")));
    }

    #[test]
    fn the_embedded_files_decompress() {
        let guide = read(GUIDE).expect("decompress the guide");
        assert!(guide.starts_with(b"<!doctype html>"));
        let python = read("docs/cheatsheets/python.md").expect("decompress the cheat sheet");
        assert!(String::from_utf8_lossy(&python).contains("Python"));
    }
}
