#![allow(unused_variables)]
#![allow(dead_code)]

// standard libraries
use std::io::{self, BufReader};
use std::io::BufWriter;
use std::fs::{self, File};
use std::path::Path;
use std::collections::BTreeMap;

// terminal ui
use colored::Colorize;

// error handling
use snafu::{Snafu, ResultExt, Backtrace};

// modules
// -- public
pub mod utils;
pub mod cache;
pub mod manifest;
pub mod lock;
// -- private
mod premake;

// internal imports
use manifest::{ManifestFile, ManifestFileParseError, LockingError};
use lock::LockFile;

// todo: convert paths to absolute
// todo: add git submodule support
// todo: contanerize code
// todo: add spinners! and loading bars
//        * spinners ==> installation
//        * loading bars ==> ??
// todo: add clean function
// todo: don't rely on git for versioning information if we're offline -> fallback to cache
// todo: deal with dependencies of multiple projects
// todo: version resolver
// todo: just write a build system?

#[derive(Debug, Snafu)]
pub enum SyncError {
    #[snafu(display("IO Error: {source} when {context}"))]
    IoError{ source: io::Error, context: String, backtrace: Backtrace },

    #[snafu(display("Failed to parse the manifest: {source}"))]
    ManifestFileParseError{ 
		#[snafu(backtrace)] // this should have an attached backtrace
    	source: ManifestFileParseError 
    },

    #[snafu(display("Failed to lock a dependency: {source}"))]
    LockError{
    	#[snafu(backtrace)] // this should have an attached backtrace
    	source: LockingError
    },

    #[snafu(display("Failed to serialize json: {source}"))]
    JsonError{ source: serde_json::Error, backtrace: Backtrace },

    #[snafu(display("Git error: {source}"))]
    Git{ source: git2::Error, backtrace: Backtrace }
}

pub struct SyncRunner<'a> {
	// vector of all the extra deps to install
	extra_deps: &'a Vec<String>,
	// path to the manifest file
	manifest_file: &'a Path,
	// path to the lock file
	lock_file: &'a Path,
	// path to the cache folder
	cache_folder: &'a Path,
	// should we force the update?
	update: bool,
	// folder overrides for specific dependencies
	overrides: BTreeMap<String, String>,
	// first time sync has been called by the configuring system?
	first: bool,

	// store the manifest file
	manifest: Option<ManifestFile>,
}

impl SyncRunner<'_> {
	fn build<'a>(extra_deps: &'a Vec<String>, manifest_file: &'a Path, lock_file: &'a Path, cache_folder: &'a Path, force_update: bool, overrides: BTreeMap<String, String>, first: bool) -> SyncRunner<'a> {
		SyncRunner { extra_deps: extra_deps, 
					 manifest_file: manifest_file, 
					 lock_file: lock_file, 
					 cache_folder: cache_folder, 
					 update: force_update, 
					 overrides: overrides, 
					 first: first,
					 manifest: None }
	}

	fn read_manifest(&mut self) -> Result<(), SyncError>{
		// try to read the manifest file
		let manifest_file_contents = fs::read_to_string(self.manifest_file).context(IoSnafu{ context: format!("reading file \"{:?}\"", self.manifest_file) })?;
		
		// serialize the manifest
		self.manifest = Some(ManifestFile::parse(&manifest_file_contents).context(ManifestFileParseSnafu)?);

		Ok(())
	}

	// compiles a manifest file to a lock file
	fn update(&mut self) -> Result<LockFile, SyncError> {
		self.read_manifest()?;

		let manifest = self.manifest.as_ref().unwrap();

		// generate the lock file information
		let mut lockfile = LockFile::new();

		lockfile.lockfile_version = manifest.manifest_version;

		// todo: break out into separate method
		let default_group = String::from("dependencies");
		let mut dep_groups = vec![&default_group];
		dep_groups.extend(self.extra_deps.iter());

		for dep_group in dep_groups {
			for dep in &manifest.dependencies[dep_group] {
				lockfile.dependencies.insert(dep.name.clone(), dep.lock().context(LockSnafu)?);
			}
		}

		// write the lock file
		if self.first {
			println!("{} {}", "Writing".green(), "wares.lock".yellow());
			serde_json::to_writer(BufWriter::new(File::create(self.lock_file).context(IoSnafu{ context: format!("creating \"{:?}\"", self.lock_file) })?), &lockfile).context(JsonSnafu)?;
		} else {
			println!("{} {}", "Merging".cyan(), "wares.lock".yellow());
			let mut parent_lockfile: LockFile = serde_json::from_reader(BufReader::new(File::open(self.lock_file).context(IoSnafu{ context: format!("opening {:?}", self.lock_file) })?)).context(JsonSnafu)?;
			parent_lockfile.merge(&lockfile);
			serde_json::to_writer(BufWriter::new(File::create(self.lock_file).context(IoSnafu{ context: format!("creating \"{:?}\"", self.lock_file) })?), &parent_lockfile).context(JsonSnafu)?;
		}

		Ok(lockfile)
	}

	// ensures all the dependencies specified by a lock file are installed on the system and returns their paths
	fn install(&mut self, lockfile: LockFile) -> Result<BTreeMap<String, String>, SyncError> {
		// read the manifest in if we haven't already
		if let None = self.manifest {
			self.read_manifest()?;
		}

		let manifest = self.manifest.as_ref().unwrap();

		let default_group = String::from("dependencies");
		let mut dep_groups = vec![&default_group];
		dep_groups.extend(self.extra_deps.iter());
		let my_dependencies: Vec<&str> = manifest.dep_names(&dep_groups);

		let mut installation_info: BTreeMap<String, String> = BTreeMap::new();

		// add all of the overrides that apply to our folder to the installation_info
		for (name, folder) in &self.overrides {
			if my_dependencies.contains(&name.as_str()) {
				// the folder location should be absolute to the root wares path so that overrides actually function correctly
				let full_path = utils::get_full_path(folder).context(IoSnafu{ context: format!("grabbing full path of {folder}") })?;
				installation_info.insert(name.clone(), full_path.to_str().expect("Path contains invalid Unicode characters").to_string());
			}
		}
		
		for (name, dependency) in lockfile.dependencies {
			if !installation_info.contains_key(&name) && my_dependencies.contains(&name.as_str()) {
				installation_info.insert(name, dependency.install(self.cache_folder)?);
			}
		}

		Ok(installation_info)
	}

	pub fn needs_update(&self) -> bool {
		self.update || 
			!self.lock_file.exists() || 
			self.manifest_file.metadata().is_ok_and(
				|manifest_data| manifest_data.modified().is_ok_and(
					|manifest_time| self.lock_file.metadata().is_ok_and(
						|lock_data| lock_data.modified().is_ok_and(
							|lock_time| manifest_time > lock_time)))) // these lines check if the manifest file was edited more recently than the lock file
	}

	// sync - check for update and then install dependencies
	pub fn sync(&mut self) -> Result<BTreeMap<String, String>, SyncError> {
		let lockfile = if self.needs_update() {
			self.update()?
		} else {
			serde_json::from_reader(BufReader::new(File::open(self.lock_file).context(IoSnafu{context: format!("opening \"{:?}\"", self.lock_file)})?)).context(JsonSnafu)? // else read from the lock file
		};

		self.install(lockfile)
	}
}