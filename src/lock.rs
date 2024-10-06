// standard libraries
use std::sync::OnceLock;
use std::path::Path;
use std::collections::BTreeMap;
use std::fmt;

// git2
use git2::Repository;
use git2::build::RepoBuilder;

// regex
use regex::Regex;

// serialization/deserialization
use serde::{Serialize, Deserialize};
use serde::ser::{Serializer, SerializeMap};
use serde::de::{Deserializer, Visitor, Error};

// terminal ui
use spinoff::{Spinner, spinners, Color};

// error handling
use snafu::ResultExt;

// internal dependencies
use crate::utils;
use crate::{SyncError, IoSnafu, GitSnafu};

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
	pub fn new(url: String, id: LockedDependencyId) -> Self {
		LockedDependency { url: url, id: id }
	}

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

	// installs the github repository into the cache specified at path 
	// returns the installation folder as a string
	pub fn install(&self, cache_path: &Path) -> Result<String, SyncError> {
		let mut install_path = utils::get_full_path(cache_path).context(IoSnafu{ context: format!("grabbing full path of {:?}", cache_path) })?; // might? error out if the cache doesn't exist yet
		install_path.push(self.uuid()); // this path should now be absolute

		if !install_path.exists() {
			let mut spinner = Spinner::new(spinners::Dots, format!("Installing {} to {}", self.url, install_path.display()), Color::Blue);

			match self.id {
				LockedDependencyId::Oid(oid) => {
					// git doesn't allow cloning a commit directly, so instead we:
					// (1) initalize an empty repository
					let repository = Repository::init(&install_path).context(GitSnafu)?;
					
					// (2) add the remote url as the origin
					let mut origin = repository.remote("origin", &self.url).context(GitSnafu)?;
					
					// (3) fetch the specific revision
					origin.fetch(&[oid.to_string()], Some(git2::FetchOptions::new().depth(1)), None).context(GitSnafu)?;
					
					// (4) reset the branch to the revision of interest
					repository.reset(&repository.find_object(oid, None).context(GitSnafu)?, git2::ResetType::Hard, None).context(GitSnafu)?;  
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

					clone_builder.clone(&self.url, &install_path).context(GitSnafu)?;
				}
			}

			spinner.success("Done!");
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
	pub lockfile_version: i64,
	//features: BTreeMap<String, Vec<String>>,
	pub dependencies: BTreeMap<String, LockedDependency>
}

impl LockFile {
	pub fn new() -> LockFile {
		LockFile { lockfile_version: 0, dependencies: BTreeMap::new() }
	}

	pub fn merge(&mut self, other: &LockFile) {
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