#![allow(unused_variables)]
#![allow(dead_code)]

use std::io::{self, BufReader};
use std::io::BufWriter;
use std::fmt;
use std::fs::{self, File};
use std::path::Path;
use std::collections::BTreeMap;
use std::sync::OnceLock;

use git2::build::RepoBuilder;
use toml::{Table, Value};

use serde::{Serialize, Deserialize};
use serde::ser::{Serializer, SerializeMap};
use serde::de::{Deserializer, Visitor, Error};

use semver::{Version, VersionReq};

use regex::Regex;

use git2::{Remote, Repository};

use colored::Colorize;

pub mod utils;
mod premake;

// todo: only return dependencies that are a part of this manifest file.
// todo: contanerize code
// todo: add spinners! and loading bars
// todo: add clean function
// todo: don't rely on git for versioning information if we're offline -> fallback to cache
// todo: deal with dependencies of multiple projects
// todo: version resolver
// todo: just write a build system?

#[derive(Debug)]
pub enum Specifier {
	MainBranch,
	Branch(String),
	CommitHash([u8; 20]), // hash value? 40 hexadecimal digits ==> array of u8
	Tag(String),
	Rev(String),
	Version(VersionReq)
}

#[derive(Debug)]
pub struct ManifestDependency {
	name: String,
	repo_url: String,
	specifier: Specifier,
	//premake_include: bool,
	//cmake_include: bool,

	// version: semver, // version or commit or revision or branch or tag
}

#[derive(thiserror::Error, Debug)]
pub enum DependencyParseError {
	#[error("Missing the {0} key in dependency.")]
	MissingKey(&'static str),

	#[error("The {key} key must be of type {required_type}.")]
	WrongType{key: &'static str, required_type: &'static str},

	#[error("Missing dependency specifier. One of: version, commit, rev, branch or tag required")]
	MissingSpecifier,

	#[error("Dependency type {0} is unknown.")]
	UnknownProvider(String),

	#[error("Failed to parse the semantic verion")]
	SemverParse(#[from] semver::Error),

	#[error("Failed to parse the commit hash")]
	CommitParse(#[from] std::num::ParseIntError),

	#[error("Failed to parse the specifier from {0}")]
	SpecifierParseError(String)
}

#[derive(thiserror::Error, Debug)]
pub enum LockingError {
	#[error("Git backend error")]
	Git(#[from] git2::Error),

	#[error("Regex error")]
	Regex(#[from] regex::Error),

	#[error("Version parse error")]
	Version(#[from] semver::Error),

	#[error("Failed to find a version matching the version requirement: {0}")]
	NoMatch(String),

	#[error("Failed to find the tag specified: {0}")]
	NoTag(String),

	#[error("Failed to find the rev specified: {0}")]
	NoRev(String)
}

impl ManifestDependency {
	fn unnamed(repo_url: String, specifier: Specifier) -> ManifestDependency {
		ManifestDependency { name: String::from(""), repo_url: repo_url, specifier: specifier }
	}

	fn parse(toml_value: &Value) -> Result<ManifestDependency, DependencyParseError> {
		match toml_value {
			Value::String(dep_str) => {
				fn parse_specifier(end_of_dep: &str) -> Result<Specifier, DependencyParseError> {
					if end_of_dep.is_empty() {
						return Ok(Specifier::MainBranch)
					}

					match &end_of_dep[..1] {
						"@" => Ok(Specifier::Version(VersionReq::parse(&end_of_dep[1..])?)),
						"/" => Ok(Specifier::Branch(end_of_dep[1..].to_string())),
						"!" => Ok(Specifier::Rev(end_of_dep[1..].to_string())),
						"#" => Ok(Specifier::Tag(end_of_dep[1..].to_string())),
						_ => Err(DependencyParseError::SpecifierParseError(end_of_dep.to_string()))
					}
				}

				let type_end = dep_str.find(":").expect("Missing semicolon in dependency string");
				let dep_type = &dep_str[0..type_end];

				static USERNAME_REPOSITORY_REGEX: OnceLock<Regex> = OnceLock::new();
				let username_repository_regex = USERNAME_REPOSITORY_REGEX.get_or_init(|| Regex::new(r"[\w-]+/[\w-]+").unwrap());

				let (url, specifier) = if dep_type == "gh" || dep_type == "github" {
					let username_repository = username_repository_regex.find(&dep_str[type_end..]).expect("Failed to parse github info");
					let specifier = parse_specifier(&dep_str[(type_end + username_repository.end())..])?;
					(format!("https://github.com/{}.git", username_repository.as_str()), specifier)
				} else if dep_type == "gl" || dep_type == "gitlab" {
					let username_repository = username_repository_regex.find(&dep_str[type_end..]).expect("Failed to parse gitlab info");
					let specifier = parse_specifier(&dep_str[(type_end + username_repository.end())..])?;
					(format!("https://gitlab.com/{}.git", username_repository.as_str()), specifier)
				} else if dep_type == "git" {
					static GIT_REGEX: OnceLock<Regex> = OnceLock::new();
					let git_regex = GIT_REGEX.get_or_init(|| Regex::new(r"https://[\w\.@\:/\-~]+.git").unwrap());
					let url_match = git_regex.find(&dep_str[type_end..]).expect("Failed to find git url");
					let specifier = parse_specifier(&dep_str[(type_end + url_match.end())..])?;
					(url_match.as_str().to_string(), specifier)
				} else {
					return Err(DependencyParseError::UnknownProvider(dep_type.to_string()))
				};

				Ok(ManifestDependency::unnamed(url, specifier))
			},
			Value::Table(dep_table) => {
				// returns a Result of the string corresponding with the key or an error if no string was found
				fn get_str<'a>(map: &'a toml::map::Map<String, Value>, key: &'static str) -> Result<&'a str, DependencyParseError> {
					Ok(map.get(key)
						.ok_or(DependencyParseError::MissingKey(key))? // enforce existence
						.as_str().ok_or(DependencyParseError::WrongType { key: key, required_type: "string" })?) // check type
				}

				let dep_type: &str = get_str(&dep_table, "type")?;
				
				let repo_url: String = match dep_type {
					"git" => String::from(get_str(&dep_table, "url")?),
					"github" | "gh" => format!("https://github.com/{}/{}.git", get_str(&dep_table, "username")?, get_str(&dep_table, "repository")?),
					"gitlab" | "gl" => format!("https://gitlab.com/{}/{}.git", get_str(&dep_table, "username")?, get_str(&dep_table, "repository")?),
					_ => return Err(DependencyParseError::UnknownProvider(dep_type.to_string())) // we don't know this one
				};

				let specifier = if dep_table.contains_key("version") {
					Specifier::Version(VersionReq::parse(get_str(&dep_table, "version")?)?)
				} else if dep_table.contains_key("commit") {
					Specifier::CommitHash(utils::parse_hex::<20>(get_str(&dep_table, "commit")?)?)
				} else if dep_table.contains_key("rev") {
					Specifier::Rev(get_str(&dep_table, "rev")?.to_string())
				} else if dep_table.contains_key("branch") {
					Specifier::Branch(get_str(&dep_table, "rev")?.to_string())
				} else if dep_table.contains_key("tag") {
					Specifier::Tag(get_str(&dep_table, "rev")?.to_string())
				} else {
					Specifier::MainBranch // main branch, echo warning?
				};

				Ok(ManifestDependency::unnamed(repo_url, specifier))
			},
			_ => {
				Err(DependencyParseError::WrongType { key: "type", required_type: "string or table" })
			}
		}
	}

	fn lock(&self) -> Result<LockedDependency, LockingError> {
		match &self.specifier {
			Specifier::MainBranch => Ok(LockedDependency { url: self.repo_url.clone(), id: LockedDependencyId::MainBranch }), // TODO: update to actual choose the default branch
			Specifier::Branch(branch) => Ok(LockedDependency { url: self.repo_url.clone(), id: LockedDependencyId::Branch(branch.clone()) }),
			//Specifier::CommitHash(hash) => LockedDependency { url: self.repo_url, rev: utils::encode_hex(hash) },
			Specifier::Version(requirement) => {
				// git ls-remote
				// parse the remote refs for version information
				// i wish i could put this in a function
				let mut remote = Remote::create_detached(self.repo_url.clone())?;
				remote.connect(git2::Direction::Fetch)?;
				let refs = remote.list()?;

				let mut versions: BTreeMap<Version, git2::Oid> = BTreeMap::new();

				// this is one girthy regex! recommend regex101 or other regex validator
				static VERSION_REGEX: OnceLock<Regex> = OnceLock::new();
				let version_regex = VERSION_REGEX.get_or_init(|| Regex::new(r"refs/tags/v?((?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*))?(?:\.(?:0|[1-9]\d*))?(?:-(?:(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?:[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?)").unwrap());
				
				for git_ref in refs {
					let potential_version_str = git_ref.name();
					match version_regex.captures(potential_version_str) {
						Some(captures) => {
							// stop gap solution to try fixing the version requirement by adding .0 (0 to 2 times)
							let mut version = String::from(&captures[1]);

							let version_groups = captures[1].chars().filter(|x| *x == '.').count() + 1;
							for i in version_groups..3 {
								version += ".0";
							}

							versions.insert(Version::parse(&version)?, git_ref.oid());
						},
						_ => {}
					}
				}

				// extract the latest version that matches the requirements from the versions map
				let mut oid = git2::Oid::zero();

				for version in versions.keys().rev() {
					// find the latest match
					if requirement.matches(version) {
						oid = versions[version];
						break;
					}
				}

				if oid.is_zero() {
					return Err(LockingError::NoMatch(requirement.to_string()));
				}

				Ok(LockedDependency { url: self.repo_url.clone(), id: LockedDependencyId::Oid(oid) })
			},
			Specifier::Tag(tag) => {
				// i wish i could put this in a function
				let mut remote = Remote::create_detached(self.repo_url.clone())?;
				remote.connect(git2::Direction::Fetch)?;
				let refs = remote.list()?;

				let mut oid = git2::Oid::zero();
				// matches refs/tags/...
				let tag_regex = Regex::new(&format!("refs/tags/{}", &tag))?;
				for git_ref in refs {
					match tag_regex.captures(git_ref.name()) {
						Some(captures) => {
							oid = git_ref.oid();
							break;
						},
						_ => {}
					}
				}

				if oid.is_zero() {
					return Err(LockingError::NoTag(tag.clone()))
				}

				Ok(LockedDependency { url: self.repo_url.clone(), id: LockedDependencyId::Oid(oid) })
			},
			Specifier::Rev(rev) => {
				// i wish i could put this in a function
				let mut remote = Remote::create_detached(self.repo_url.clone())?;
				remote.connect(git2::Direction::Fetch)?;
				let refs = remote.list()?;

				let mut oid = git2::Oid::zero();

				for git_ref in refs {
					if rev == git_ref.name() {
						oid = git_ref.oid();
						break;
					}
				}

				if oid.is_zero() {
					return Err(LockingError::NoRev(rev.clone()));
				}

				Ok(LockedDependency { url: self.repo_url.clone(), id: LockedDependencyId::Oid(oid) })
			}
			Specifier::CommitHash(hash) => {
				Ok(LockedDependency{ url: self.repo_url.clone(), 
									 id: LockedDependencyId::Oid(git2::Oid::from_bytes(hash)?)}) // this is a big line!
			}
		}
	}
}

#[derive(Debug)]
pub struct ManifestFile {
	manifest_version: i64,
	dependencies: BTreeMap<String, Vec<ManifestDependency>>
}

#[derive(thiserror::Error, Debug)]
pub enum ManifestFileParseError {
	#[error("Missing key: {0} in manifest file.")]
	MissingKey(&'static str),

	#[error("Wrong type for key: {0}")]
	WrongType(String),

	#[error("TOML parse error")]
	TOML(#[from] toml::de::Error),

	#[error("Dependency parse error")]
	DependencyParse(#[from] DependencyParseError)
}

impl ManifestFile {
	fn parse(info: &str) -> Result<ManifestFile, ManifestFileParseError> {
		let toml_table = info.parse::<Table>()?;

		// empty file
		let mut manifest = ManifestFile { 
			manifest_version: toml_table.get("manifest_version")
										.ok_or(ManifestFileParseError::MissingKey("manifest_version"))?
										.as_integer().ok_or(ManifestFileParseError::WrongType("manifest_version".to_string()))?, 
			dependencies: BTreeMap::new() 
		};

		// fill out dependencies
		for key in toml_table.keys().filter(|key| *key != "manifest_version") {
			match &toml_table[key] {
				Value::Table(deps) => {
					let mut dependency_group: Vec<ManifestDependency> = Vec::new();
					
					for (dep_name, dep_spec) in deps {
						let mut dep = ManifestDependency::parse(dep_spec)?;
						dep.name = dep_name.clone();
						dependency_group.push(dep);
					}

					manifest.dependencies.insert(key.to_string(), dependency_group);
				},
				_ => {
					// if its not a table, it's an error
					return Err(ManifestFileParseError::WrongType(key.clone()));
				}
			}
		}

		Ok(manifest)
	}
}

#[derive(Clone, Debug)]
pub enum LockedDependencyId {
	MainBranch, // no value provided besides the url by the user
	Branch(String), // a branch provided by the user
	Oid(git2::Oid) // a commit hash, rev, tag, or version requirement provided by the user
}

#[derive(Clone, Debug)]
pub struct LockedDependency {
	url: String, // git/github/gitlab url associated with this dependency
	id: LockedDependencyId, // commit/version (aka tag)/revision/branch associated with this dependency
}

impl LockedDependency {
	fn uuid(&self) -> String {
		static GITHUB_REGEX: OnceLock<Regex> = OnceLock::new();
		let github_regex = GITHUB_REGEX.get_or_init(|| { Regex::new(r"https://github\.com/([A-Za-z0-9_.-]*)/([A-Za-z0-9_.-]*).git").unwrap() });

		static GITLAB_REGEX: OnceLock<Regex> = OnceLock::new();
		let gitlab_regex = GITLAB_REGEX.get_or_init(|| { Regex::new(r"https://gitlab\.com/([A-Za-z0-9_.-]*)/([A-Za-z0-9_.-]*).git").unwrap() });

		static URL_REGEX: OnceLock<Regex> = OnceLock::new();
		let url_regex = URL_REGEX.get_or_init(|| { Regex::new(r"(?:https://)?(?:www\.)?([A-Za-z0-9_.-/]*).git").unwrap() });

		let start = if let Some(github) = github_regex.captures(&self.url) {
			format!("gh-{}-{}", &github[1], &github[2])
		} else if let Some(gitlab) = gitlab_regex.captures(&self.url) {
			format!("gl-{}-{}", &gitlab[1], &gitlab[2])
		} else if let Some(url) = url_regex.captures(&self.url) {
			utils::sanitize_filename(&url[1])
		} else {
			utils::sanitize_filename(&self.url)
		};
		
		match &self.id {
			LockedDependencyId::MainBranch => {
				format!("{}-latest", start)
			},
			LockedDependencyId::Branch(name) => {
				format!("{}-{}-latest", start, &name)
			},
			LockedDependencyId::Oid(oid) => {
				format!("{}-{}", start, oid)
			}
		}
	}

	// installs the github repository into the cache specified at path and returns the installation folder as a string
	fn install(&self, cache_path: &Path) -> Result<String, SyncError> {
		let mut install_path = cache_path.to_path_buf();
		install_path.push(self.uuid());

		if !install_path.exists() {
			println!("Installing {} to {}", self.url, install_path.display());
			match self.id {
				LockedDependencyId::Oid(oid) => {
					// git doesn't allow cloning a commit directly, so instead we:
					let repository = Repository::init(&install_path)?; // initalize an empty repository
					let mut origin = repository.remote("origin", &self.url)?; // add the remote url as the origin
					origin.fetch(&[oid.to_string()], Some(git2::FetchOptions::new().depth(1)), None)?; // fetch the specific revision
					repository.reset(&repository.find_object(oid, None)?, git2::ResetType::Hard, None)?;  // reset the branch to the revision of interest
				}
				_ => {
					// main branch or specific one
					// todo: add branch update
					let mut clone_builder = RepoBuilder::new();
					let mut fetch_options = git2::FetchOptions::new();
					fetch_options.depth(1);
					clone_builder.fetch_options(fetch_options);

					if let LockedDependencyId::Branch(branch) = &self.id {
						clone_builder.branch(branch);
					}

					clone_builder.clone(&self.url, &install_path)?;
				}
			}
		}

		Ok(String::from(install_path.to_str().expect("Non UTF-8 character in path")))
	}
}

impl Serialize for LockedDependency {
	fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
    	let size = if let LockedDependencyId::MainBranch = self.id { Some(1) } else { Some(2) };
        let mut map = serializer.serialize_map(size)?;
        map.serialize_entry("url", &self.url)?;

        match &self.id {
        	LockedDependencyId::Branch(name) => {
        		map.serialize_entry("branch", &name)?;
        	},
        	LockedDependencyId::Oid(oid) => {
        		map.serialize_entry("oid", &oid.to_string())?;
        	},
        	_ => {}
        }

        map.end()
    }
}

impl<'de> Deserialize<'de> for LockedDependency {
    fn deserialize<D>(deserializer: D) -> Result<LockedDependency, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_map(LockedDependencyVisitor)
    }
}

struct LockedDependencyVisitor;

impl<'de> Visitor<'de> for LockedDependencyVisitor {
    type Value = LockedDependency;

    fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
        formatter.write_str("a map containing the url key and optionally either a branch or oid key")
    }

    fn visit_map<A>(self, mut access: A) -> Result<Self::Value, A::Error>
        where
            A: serde::de::MapAccess<'de>, {
        let mut url: Option<String> = None;
        let mut id = LockedDependencyId::MainBranch;

        while let Some((key, value)) = access.next_entry::<String, String>()? {
        	if key == "url" {
        		url = Some(String::from(value));
        	} else if key == "branch" {
        		id = LockedDependencyId::Branch(String::from(value));
        	} else if key == "oid" {
        		id = LockedDependencyId::Oid(git2::Oid::from_str(&value).unwrap());
        	}
        }

        if let None = url {
        	return Err(A::Error::missing_field("url"));
        }

        Ok(LockedDependency { url: url.unwrap(), id: id })
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct LockFile {
	lockfile_version: i64,
	//features: BTreeMap<String, Vec<String>>,
	dependencies: BTreeMap<String, LockedDependency>
}

impl LockFile {
	fn new() -> LockFile {
		LockFile { lockfile_version: 0, dependencies: BTreeMap::new() }
	}

	fn merge(&mut self, other: &LockFile) {
		for (name, dependency) in &other.dependencies {
			if !self.dependencies.contains_key(name) {
				self.dependencies.insert(name.to_owned(), dependency.clone());
			}
		}
	} 

	/*
	fn include_feature(&mut self, pkg_name: &str, feature: &str) {
		if !self.features.contains_key(pkg_name) {
			self.features.insert(pkg_name.to_string(), vec![]);
		}

		let features_vec: &mut Vec<String> = self.features.get_mut(pkg_name).unwrap();
		features_vec.push(feature.to_string());
	}*/
}

#[derive(thiserror::Error, Debug)]
pub enum SyncError {
    #[error("IO Error")]
    IoError(#[from] io::Error),

    #[error("Failed to parse the manifest")]
    ManifestFileParseError(#[from] ManifestFileParseError),

    #[error("Failed to lock a dependency")]
    LockError(#[from] LockingError),

    #[error("Failed to serialize json")]
    JsonError(#[from] serde_json::Error),

    #[error("Git error")]
    Git(#[from] git2::Error)
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
}

impl SyncRunner<'_> {
	fn build<'a>(extra_deps: &'a Vec<String>, manifest_file: &'a Path, lock_file: &'a Path, cache_folder: &'a Path, force_update: bool, overrides: BTreeMap<String, String>, first: bool) -> SyncRunner<'a> {
		SyncRunner { extra_deps: extra_deps, 
					 manifest_file: manifest_file, 
					 lock_file: lock_file, 
					 cache_folder: cache_folder, 
					 update: force_update, 
					 overrides: overrides, 
					 first: first }
	}

	// compiles a manifest file to a lock file
	fn update(&self) -> Result<LockFile, SyncError> {
		// try to read the manifest file
		let manifest = fs::read_to_string(self.manifest_file)?;
		
		// serialize the manifest
		let manifest = ManifestFile::parse(&manifest)?;

		// generate the lock file information
		let mut lockfile = LockFile::new();

		lockfile.lockfile_version = manifest.manifest_version;

		let default_group = String::from("dependencies");
  		let mut dep_groups = vec![&default_group];
		dep_groups.extend(self.extra_deps.iter());

		for dep_group in dep_groups {
			for dep in &manifest.dependencies[dep_group] {
				lockfile.dependencies.insert(dep.name.clone(), dep.lock()?);
			}
		}

		// write the lock file
		if self.first {
			println!("{} {}", "Writing".green(), "wares.lock".yellow());
			serde_json::to_writer(BufWriter::new(File::create(self.lock_file)?), &lockfile)?;
		} else {
			println!("{} {}", "Merging".cyan(), "wares.lock".yellow());
			let mut parent_lockfile: LockFile = serde_json::from_reader(BufReader::new(File::open(self.lock_file)?))?;
			parent_lockfile.merge(&lockfile);
			serde_json::to_writer(BufWriter::new(File::create(self.lock_file)?), &parent_lockfile)?;
		}

		Ok(lockfile)
	}

	// ensures all the dependencies specified by a lock file are installed on the system and returns their paths
	fn install(&self, lockfile: LockFile) -> Result<BTreeMap<String, String>, SyncError> {
		let mut installation_info: BTreeMap<String, String> = self.overrides.clone();
		
		for (name, dependency) in lockfile.dependencies {
			if !installation_info.contains_key(&name) {
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
			serde_json::from_reader(BufReader::new(File::open(self.lock_file)?))? // else read from the lock file
		};

		self.install(lockfile)
	}
}