use leader_activity::reader::{SnapshotPoller, unix_ms};
use leader_activity::ui::ActivityUi;
use opentui::prelude::{App, AppOptions, Theme};
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::SystemTime;

const HELP: &str = "Leader Activity — tail an atomic activity snapshot

Usage:
  leader-activity --file PATH

Options:
  --file PATH   JSON snapshot to tail every 500 ms
  -h, --help    show this help

Keys:
  1 all · 2 running · 3 done · f follow newest · r refresh · q/Esc quit
";

fn main() -> ExitCode {
    match parse_args() {
        Ok(Action::Help) => {
            print!("{HELP}");
            ExitCode::SUCCESS
        }
        Ok(Action::Run(path)) => match run(path) {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("leader-activity: {error}");
                ExitCode::FAILURE
            }
        },
        Err(error) => {
            eprintln!("leader-activity: {error}\n\n{HELP}");
            ExitCode::from(2)
        }
    }
}

enum Action {
    Help,
    Run(PathBuf),
}

fn parse_args() -> Result<Action, String> {
    let mut arguments = std::env::args_os().skip(1);
    let mut file = None;
    while let Some(argument) = arguments.next() {
        if argument == "--help" || argument == "-h" {
            return Ok(Action::Help);
        }
        if argument == "--file" {
            if file.is_some() {
                return Err("--file was supplied more than once".to_owned());
            }
            let value = arguments.next().ok_or_else(|| "--file needs a path".to_owned())?;
            if value.is_empty() {
                return Err("--file needs a non-empty path".to_owned());
            }
            file = Some(PathBuf::from(value));
        } else if let Some(value) = argument.to_str().and_then(|value| value.strip_prefix("--file=")) {
            if file.is_some() {
                return Err("--file was supplied more than once".to_owned());
            }
            if value.is_empty() {
                return Err("--file needs a non-empty path".to_owned());
            }
            file = Some(PathBuf::from(value));
        } else {
            return Err(format!("unknown argument: {}", argument.to_string_lossy()));
        }
    }
    file.map(Action::Run).ok_or_else(|| "missing required --file PATH".to_owned())
}

fn run(path: PathBuf) -> Result<(), String> {
    let options = AppOptions::default().with_theme(Theme::terminal()).with_title("Leader Activity");
    let app = App::new(options).map_err(|error| error.to_string())?;
    let poller = SnapshotPoller::new(path);
    let ui = ActivityUi::build(&app, Some(poller.clone()), None, unix_ms(SystemTime::now()));
    ui.refresh_now(&app, &poller);
    app.run().map_err(|error| error.to_string())
}
