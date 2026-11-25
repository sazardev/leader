use leader_chat::reader::{SnapshotPoller, unix_ms};
use leader_chat::ui::ChatUi;
use opentui::prelude::{App, AppOptions, Theme};
use std::path::{Component, Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, SystemTime};

const HELP: &str = "Leader Chat — optional terminal chat UI

Usage:
  leader-chat --state PATH --commands PATH

Options:
  --state PATH       atomic chat snapshot JSON, polled every 100 ms
  --commands PATH    atomic command JSON destination
  -h, --help         show this help

Keys:
  Ctrl-S send · Ctrl-C stop · Ctrl-N new · Ctrl-H history · Ctrl-Q exit
  Ctrl-M model · Ctrl-P profile · Enter newline · Tab change focus
";

fn main() -> ExitCode {
    match parse_args() {
        Ok(Action::Help) => {
            print!("{HELP}");
            ExitCode::SUCCESS
        }
        Ok(Action::Run(options)) => match run(options) {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("leader-chat: {error}");
                ExitCode::FAILURE
            }
        },
        Err(error) => {
            eprintln!("leader-chat: {error}\n\n{HELP}");
            ExitCode::from(2)
        }
    }
}

#[derive(Debug)]
enum Action {
    Help,
    Run(Options),
}

#[derive(Debug)]
struct Options {
    state: PathBuf,
    commands: PathBuf,
}

fn parse_args() -> Result<Action, String> {
    parse_arguments(std::env::args_os().skip(1))
}

fn parse_arguments(arguments: impl IntoIterator<Item = std::ffi::OsString>) -> Result<Action, String> {
    let mut arguments = arguments.into_iter();
    let mut state = None;
    let mut commands = None;
    while let Some(argument) = arguments.next() {
        if argument == "--help" || argument == "-h" {
            return Ok(Action::Help);
        }
        if argument == "--state" || argument == "--commands" {
            let flag = argument.to_string_lossy().into_owned();
            if path_flag_is_set(&flag, &state, &commands) {
                return Err(format!("{flag} was supplied more than once"));
            }
            let value = arguments.next().ok_or_else(|| format!("{flag} needs a path"))?;
            if value.is_empty() {
                return Err(format!("{flag} needs a non-empty path"));
            }
            set_path(&flag, PathBuf::from(value), &mut state, &mut commands);
        } else if let Some((flag, value)) = split_path_argument(&argument) {
            if path_flag_is_set(flag, &state, &commands) {
                return Err(format!("{flag} was supplied more than once"));
            }
            if value.is_empty() {
                return Err(format!("{flag} needs a non-empty path"));
            }
            set_path(flag, PathBuf::from(value), &mut state, &mut commands);
        } else {
            return Err(format!("unknown argument: {}", argument.to_string_lossy()));
        }
    }
    let state = state.ok_or_else(|| "missing required --state PATH".to_owned())?;
    let commands = commands.ok_or_else(|| "missing required --commands PATH".to_owned())?;
    if same_file(&state, &commands) {
        return Err("--state and --commands must be different files".to_owned());
    }
    Ok(Action::Run(Options { state, commands }))
}

fn same_file(left: &Path, right: &Path) -> bool {
    let left = lexical_absolute(left);
    let right = lexical_absolute(right);
    if left == right {
        return true;
    }
    matches!((std::fs::canonicalize(&left), std::fs::canonicalize(&right)), (Ok(left), Ok(right)) if left == right)
}

fn lexical_absolute(path: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().map_or_else(|_| path.to_path_buf(), |cwd| cwd.join(path))
    };
    let mut normalized = PathBuf::new();
    for component in absolute.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            component => normalized.push(component.as_os_str()),
        }
    }
    normalized
}

fn split_path_argument(argument: &std::ffi::OsString) -> Option<(&str, &std::ffi::OsStr)> {
    let text = argument.to_str()?;
    if let Some(value) = text.strip_prefix("--state=") {
        Some(("--state", std::ffi::OsStr::new(value)))
    } else if let Some(value) = text.strip_prefix("--commands=") {
        Some(("--commands", std::ffi::OsStr::new(value)))
    } else {
        None
    }
}

fn path_flag_is_set(flag: &str, state: &Option<PathBuf>, commands: &Option<PathBuf>) -> bool {
    match flag {
        "--state" => state.is_some(),
        "--commands" => commands.is_some(),
        _ => false,
    }
}

fn set_path(flag: &str, path: PathBuf, state: &mut Option<PathBuf>, commands: &mut Option<PathBuf>) {
    match flag {
        "--state" => *state = Some(path),
        "--commands" => *commands = Some(path),
        _ => unreachable!("only validated path flags reach set_path"),
    }
}

fn run(options: Options) -> Result<(), String> {
    let app_options = AppOptions::default().with_theme(Theme::terminal()).with_title("Leader Chat");
    let app = App::new(app_options).map_err(|error| error.to_string())?;
    let poller = SnapshotPoller::new(options.state);
    let writer = leader_chat::commands::CommandWriter::new(options.commands);
    let ui = ChatUi::build(&app, Some(poller.clone()), None, writer.clone(), unix_ms(SystemTime::now()));
    ui.refresh_now(&app, &poller);
    let result = app.run().map_err(|error| error.to_string());
    if !writer.flush(Duration::from_secs(2)) {
        return Err("timed out writing a pending command".to_owned());
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;

    fn parse(arguments: &[&str]) -> Result<Action, String> {
        parse_arguments(arguments.iter().map(|value| OsString::from(*value)))
    }

    #[test]
    fn accepts_both_path_argument_forms() {
        for arguments in
            [vec!["--state", "state.json", "--commands", "commands.json"], vec!["--state=state.json", "--commands=commands.json"]]
        {
            match parse(&arguments).unwrap() {
                Action::Run(options) => {
                    assert_eq!(options.state, PathBuf::from("state.json"));
                    assert_eq!(options.commands, PathBuf::from("commands.json"));
                }
                Action::Help => panic!("expected run options"),
            }
        }
    }

    #[test]
    fn rejects_missing_duplicate_empty_and_unknown_arguments() {
        assert!(parse(&[]).unwrap_err().contains("--state"));
        assert!(parse(&["--state", "state.json"]).unwrap_err().contains("--commands"));
        assert!(parse(&["--state", "state.json", "--state=other", "--commands", "commands.json"]).unwrap_err().contains("more than once"));
        assert!(parse(&["--state=", "--commands", "commands.json"]).unwrap_err().contains("non-empty"));
        assert!(parse(&["--state", "state.json", "--commands", "commands.json", "--unknown"]).unwrap_err().contains("unknown argument"));
    }

    #[test]
    fn rejects_state_and_commands_that_name_the_same_file() {
        let error = parse(&["--state", "/tmp/chat/state.json", "--commands", "/tmp/chat/./state.json"]).unwrap_err();
        assert!(error.contains("different files"));
    }

    #[test]
    fn help_does_not_require_paths() {
        assert!(matches!(parse(&["--help"]).unwrap(), Action::Help));
        assert!(matches!(parse(&["-h"]).unwrap(), Action::Help));
    }
}
