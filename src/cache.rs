use semver::Version;

use serde::{Serialize, Deserialize};
use serde::Serializer;
use serde::ser::SerializeStruct;
use serde::de::{Deserializer, Visitor};
use std::fmt;

#[derive(Debug)]
pub enum CachedObject {
	Latest, // "latest"
	Branch(String), // "<branch>"
	// "<hash>"
	Commit([u8; 20]),
	// { "version": "<semver>", "hash": "<hash>" }
	Version {
		semver: Version,
		hash: [u8; 20]
	},
	// { "tag": "<tag>", "hash": "<hash>" }
	Tag {
		tag: String,
		hash: [u8; 20]
	},
	// { "rev": "<rev>", "hash": "<hash>" }
	Rev {
		rev: String,
		hash: [u8; 20]
	}
}

// serializer for CachedObject (see: CachedObject comments for layout)
impl Serialize for CachedObject {
	fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
    	match self {
    		CachedObject::Latest => serializer.serialize_str("latest"),
    		CachedObject::Branch(branch) => serializer.serialize_str(branch.as_str()),
    		CachedObject::Commit(commit) => serializer.serialize_str(&crate::utils::format_hex::<20>(commit)),
    		CachedObject::Version{semver, hash} => {
    			let mut version = serializer.serialize_struct("Version", 2)?;
    			version.serialize_field("version", &semver)?;
    			version.serialize_field("hash", &crate::utils::format_hex::<20>(hash))?;
    			version.end()
    		},
    		CachedObject::Tag{tag, hash} => {
    			let mut tag_struct = serializer.serialize_struct("tag", 2)?;
    			tag_struct.serialize_field("tag", &tag)?;
    			tag_struct.serialize_field("hash", &crate::utils::format_hex::<20>(hash))?;
    			tag_struct.end()
    		},
    		CachedObject::Rev{rev, hash} => {
    			let mut rev_struct = serializer.serialize_struct("rev", 2)?;
    			rev_struct.serialize_field("rev", &rev)?;
    			rev_struct.serialize_field("hash", &crate::utils::format_hex::<20>(hash))?;
    			rev_struct.end()
    		}
    	}
    }
}

// deserializer for CachedObject
struct CachedObjectVisitor;

impl<'de> Visitor<'de> for CachedObjectVisitor {
    type Value = CachedObject;

    fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
        formatter.write_str("either: \"latest\" 
        a string containing a branch name
        a string containing a commit hash
        an object with a version and hash key
        an object with a rev and hash key
        an object with a tag and hash key")
    }

    fn visit_str<E>(self, s: &str) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
    	if s == "latest" {
    		Ok(CachedObject::Latest)
    	} else if crate::utils::is_valid_hash(s) {
    		Ok(CachedObject::Commit(crate::utils::parse_hex::<20>(s).expect("utils::is_valid_hash failed!")))
    	} else {
       		Ok(CachedObject::Branch(s.to_string()))
       }
    }
}

impl<'de> Deserialize<'de> for CachedObject {
    fn deserialize<D>(deserializer: D) -> Result<CachedObject, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(CachedObjectVisitor)
    }
}

#[derive(Serialize, Deserialize)]
pub struct CachedDependency {
	id: String,
	installed: Vec<CachedObject>
}