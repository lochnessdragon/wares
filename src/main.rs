use std::{collections::BTreeMap, env};

use wares_native::sync;

use std::path::PathBuf;
use clap::{Parser, Subcommand};

use colored::Colorize;

// wares sync [enabled_groups]... --root="" --current=""
#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
	#[command(subcommand)]
	command: Command
}

#[derive(Subcommand)]
enum Command {
	// Syncs up the dependencies of a project
	// sync [dev-dependencies, desktop-dependencies]	; a list of the extra dep groups to install
	//      --root="path/to/main/folder"				; path to the folder that contains (or should contain) the wares.lock file
	//      --current="path/to/current/folder"			; path to the folder that contains the current wares.toml file
	//      --cache="path/to/cache"						; path to the cache directory (defaults to WARES_CACHE environment variable, or, failing that ./wares_cache in the root directory)
	//      --first?									; is this the first call to wares sync for this run? (i.e. should the lock file be considered outdated)
	//      --override:xxx="path/to/other/dir"          ; override the installation directory for a specific dependency (xxx)
	//      --override=glfw:"path/to/glfw/dir"
	Sync {
		// A list of all the extra dependencies we should download
		enabled_groups: Vec<String>,

		// Sets the root directory (where the lockfile is stored) (defaults to cwd)
		#[arg(short, long, value_name = "DIRECTORY", help = "the directory containing wares.lock")]
		root: Option<PathBuf>,

		// Sets the current directory (where wares.toml is located) (defaults to cwd)
		#[arg(short, long, value_name = "DIRECTORY", help = "the directory containing wares.toml")]
		current: Option<PathBuf>,

		// Sets the directory that the cache is stored in
		#[arg(long, short = 'a', value_name = "DIRECTORY", help = "the cache directory")]
		cache: Option<PathBuf>,

		// is this the first time we're running the sync command? (used for interfacing with cmake, so don't show it to the user)
		#[arg (hide = true, long, short)]
		first: bool,

		// flag to indicate that we should output json instead of formatted text
		#[arg (hide = true, long, short)]
		backend: bool,

		// path overrides for dependencies
		//#[arg(long)]
		#[arg(last = true, value_name = "OVERRIDES")]
		var_args: Vec<String>
	}
}

fn main() {
	let cli = Cli::parse();

	match &cli.command {
		Command::Sync { enabled_groups, root, current, cache, first, backend, var_args } => {
			// read in any overrides
			let mut overrides: BTreeMap<String, String> = BTreeMap::new();

			for arg in var_args {
				if arg.starts_with("--override:") {
					let split_arg: Vec<&str> = arg[11..].splitn(2, '=').collect();
					overrides.insert(split_arg[0].to_string(), split_arg[1].to_string());
				}
			}

			// convert the manifest folder to a manifest file path
			let mut manifest_file: PathBuf = root.clone().unwrap_or(PathBuf::from("./"));
			manifest_file.push("wares");
			manifest_file.set_extension("toml");

			// convert the lock file folder to a lock file path
			let mut lock_file: PathBuf = current.clone().unwrap_or(PathBuf::from("./"));
			lock_file.push("wares");
			lock_file.set_extension("lock");

			// find the cache directory or a fallback
			let cache_dir: PathBuf = cache.clone().unwrap_or_else(utils::cache_dir_fallback);

			let mut sync_runner = SyncRunner::build(&enabled_groups, &manifest_file, &lock_file, &cache_dir, !*backend, overrides, *first);

			// force sync if backend output is not set
			match sync_runner.sync() {
				Ok(map) => {
					if *backend {
						serde_json::to_writer(std::io::stdout(), &map);
					} else {
						for (name, folder) in map {
							println!("{} installed to: {}", name.green(), folder.yellow());
						}
					}
				},
				Err(error) => {
					println!("{error}");
				},
			} 
		}
	}
}
