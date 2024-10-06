use std::collections::BTreeMap;
use std::sync::OnceLock;

// repositories
use git2::Remote;

// regex
use regex::Regex;

// serialization/deserialization
use toml::{Table, Value};

// versioning
use semver::{Version, VersionReq};

// error handling
use snafu::{Snafu, ResultExt, Backtrace};

// internal imports
use crate::utils;

use crate::lock::{LockedDependency, LockedDependencyId};

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
	pub name: String,
	repo_url: String,
	specifier: Specifier,
	//premake_include: bool,
	//cmake_include: bool,

	// version: semver, // version or commit or revision or branch or tag
}

#[derive(Debug, Snafu)]
pub enum DependencyParseError {
	// todo: add group + context information
	#[snafu(display("Missing the {key} key in dependency."))]
	DepMissingKey{ key: &'static str },

	// todo: add line + column information w/ context
	#[snafu(display("The {key} key must of of type {required_type}."))]
	DepWrongType{ key: &'static str, required_type: &'static str },

	// todo: add line + column information w/ context
	#[snafu(display("Missing dependency specifier. One of: version, commit, rev, branch or tag required"))]
	MissingSpecifier,

	// todo: add line + column information w/ context
	#[snafu(display("Dependency type {provider_id} is unknown."))]
	UnknownProvider{ provider_id: String },

	// todo: print context + column information
	#[snafu(display("Failed to parse the semantic verion: {source}"))]
	SemverParse{ source: semver::Error },

	// todo: print context + column information
	#[snafu(display("Failed to parse the commit hash: {source}"))]
	CommitParse{source: std::num::ParseIntError},

	#[snafu(display("Failed to parse the specifier from {specifier}"))]
	SpecifierParseError{ specifier: String }
}

#[derive(Debug, Snafu)]
pub enum LockingError {
	#[snafu(display("Git backend error: {source}"))]
	Git{ source: git2::Error, backtrace: Backtrace },

	#[snafu(display("Regex error: {source}"))]
	Regex{source: regex::Error},

	#[snafu(display("Version parse error: {source}"))]
	Version{source: semver::Error},

	#[snafu(display("Failed to find a version matching the version requirement: {requirement}"))]
	NoMatch{ requirement: String },

	#[snafu(display("Failed to find the tag specified: {tag}"))]
	NoTag{ tag: String },

	#[snafu(display("Failed to find the rev specified: {rev}"))]
	NoRev{ rev: String }
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
						"@" => Ok(Specifier::Version(
							VersionReq::parse(&end_of_dep[1..]).context(SemverParseSnafu{})?
						)),
						"/" => Ok(Specifier::Branch(end_of_dep[1..].to_string())),
						"!" => Ok(Specifier::Rev(end_of_dep[1..].to_string())),
						"#" => Ok(Specifier::Tag(end_of_dep[1..].to_string())),
						_ => Err(DependencyParseError::SpecifierParseError{specifier: end_of_dep.to_string()})
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
					return Err(DependencyParseError::UnknownProvider{ provider_id: dep_type.to_string() })
				};

				Ok(ManifestDependency::unnamed(url, specifier))
			},
			Value::Table(dep_table) => {
				// returns a Result of the string corresponding with the key or an error if no string was found
				fn get_str<'a>(map: &'a toml::map::Map<String, Value>, key: &'static str) -> Result<&'a str, DependencyParseError> {
					Ok(map.get(key)
						.ok_or(DependencyParseError::DepMissingKey{ key: key })? // enforce existence
						.as_str().ok_or(DependencyParseError::DepWrongType { key: key, required_type: "string" })?) // check type
				}

				let dep_type: &str = get_str(&dep_table, "type")?;
				
				let repo_url: String = match dep_type {
					"git" => String::from(get_str(&dep_table, "url")?),
					"github" | "gh" => format!("https://github.com/{}/{}.git", get_str(&dep_table, "username")?, get_str(&dep_table, "repository")?),
					"gitlab" | "gl" => format!("https://gitlab.com/{}/{}.git", get_str(&dep_table, "username")?, get_str(&dep_table, "repository")?),
					_ => return Err(DependencyParseError::UnknownProvider{ provider_id: dep_type.to_string() }) // we don't know this one
				};

				let specifier = if dep_table.contains_key("version") {
					Specifier::Version(
						VersionReq::parse(get_str(&dep_table, "version")?).context(SemverParseSnafu{})?
					)
				} else if dep_table.contains_key("commit") {
					Specifier::CommitHash(
						utils::parse_hex::<20>(get_str(&dep_table, "commit")?).context(CommitParseSnafu{})?
					)
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
				Err(DependencyParseError::DepWrongType { key: "type", required_type: "string or table" })
			}
		}
	}

	pub fn lock(&self) -> Result<LockedDependency, LockingError> {
		match &self.specifier {
			Specifier::MainBranch => Ok(LockedDependency::new(self.repo_url.clone(), LockedDependencyId::MainBranch)), // TODO: update to actual choose the default branch
			Specifier::Branch(branch) => Ok(LockedDependency::new(self.repo_url.clone(), LockedDependencyId::Branch(branch.clone()))),
			Specifier::Version(requirement) => {
				// git ls-remote
				// parse the remote refs for version information
				// i wish i could put this in a function
				let mut remote = Remote::create_detached(self.repo_url.clone()).context(GitSnafu{})?;
				remote.connect(git2::Direction::Fetch).context(GitSnafu{})?;
				let refs = remote.list().context(GitSnafu{})?;

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

							versions.insert(Version::parse(&version).context(VersionSnafu)?, git_ref.oid());
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
					return Err(LockingError::NoMatch{ requirement: requirement.to_string()});
				}

				Ok(LockedDependency::new(self.repo_url.clone(), LockedDependencyId::Oid(oid)))
			},
			Specifier::Tag(tag) => {
				// i wish i could put this in a function
				let mut remote = Remote::create_detached(self.repo_url.clone()).context(GitSnafu)?;
				remote.connect(git2::Direction::Fetch).context(GitSnafu)?;
				let refs = remote.list().context(GitSnafu)?;

				let mut oid = git2::Oid::zero();
				// matches refs/tags/...
				let tag_regex = Regex::new(&format!("refs/tags/{}", &tag)).context(RegexSnafu)?;
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
					return Err(LockingError::NoTag{ tag: tag.clone() })
				}

				Ok(LockedDependency::new(self.repo_url.clone(), LockedDependencyId::Oid(oid)))
			},
			Specifier::Rev(rev) => {
				// i wish i could put this in a function
				let mut remote = Remote::create_detached(self.repo_url.clone()).context(GitSnafu)?;
				remote.connect(git2::Direction::Fetch).context(GitSnafu)?;
				let refs = remote.list().context(GitSnafu)?;

				let mut oid = git2::Oid::zero();

				for git_ref in refs {
					if rev == git_ref.name() {
						oid = git_ref.oid();
						break;
					}
				}

				if oid.is_zero() {
					return Err(LockingError::NoRev{ rev: rev.clone() });
				}

				Ok(LockedDependency::new(self.repo_url.clone(), LockedDependencyId::Oid(oid)))
			}
			Specifier::CommitHash(hash) => {
				Ok(LockedDependency::new(self.repo_url.clone(), 
									 LockedDependencyId::Oid(git2::Oid::from_bytes(hash).context(GitSnafu)?))) // this is a big line!
			}
		}
	}
}

#[derive(Debug)]
pub struct ManifestFile {
	pub manifest_version: i64,
	pub dependencies: BTreeMap<String, Vec<ManifestDependency>>
}

#[derive(Debug, Snafu)]
pub enum ManifestFileParseError {
	#[snafu(display("Missing key: {key} in manifest file."))]
	ManifestMissingKey{ key: &'static str },

	#[snafu(display("Wrong type for key: {key}"))]
	ManifestWrongType{ key: String },

	#[snafu(display("TOML parse error: {source}"))]
	TOML{ source: toml::de::Error },

	#[snafu(display("Dependency parse error: {source}"))]
	DependencyParse{ source: DependencyParseError }
}

impl ManifestFile {
	pub fn parse(info: &str) -> Result<ManifestFile, ManifestFileParseError> {
		let toml_table = info.parse::<Table>().context(TOMLSnafu)?;

		// empty file
		let mut manifest = ManifestFile { 
			manifest_version: toml_table.get("manifest_version")
										.ok_or(ManifestFileParseError::ManifestMissingKey{ key: "manifest_version" })?
										.as_integer().ok_or(ManifestFileParseError::ManifestWrongType{ key: "manifest_version".to_string() })?, 
			dependencies: BTreeMap::new() 
		};

		// fill out dependencies
		for key in toml_table.keys().filter(|key| *key != "manifest_version") {
			match &toml_table[key] {
				Value::Table(deps) => {
					let mut dependency_group: Vec<ManifestDependency> = Vec::new();
					
					for (dep_name, dep_spec) in deps {
						let mut dep = ManifestDependency::parse(dep_spec).context(DependencyParseSnafu)?;
						dep.name = dep_name.clone();
						dependency_group.push(dep);
					}

					manifest.dependencies.insert(key.to_string(), dependency_group);
				},
				_ => {
					// if its not a table, it's an error
					return Err(ManifestFileParseError::ManifestWrongType{ key: key.clone() });
				}
			}
		}

		Ok(manifest)
	}

	pub fn dep_names(&self, dep_groups: &Vec<&String>) -> Vec<&str> {
		let mut dep_names: Vec<&str> = vec![];
		for group in dep_groups {
			for dep in &self.dependencies[*group] {
				dep_names.push(&dep.name);
			}
		}

		dep_names
	}
}