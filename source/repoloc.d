module tamias.repoloc;

import tamias.config;

import std.path : buildPath;
import std.string : tr, chomp, chompPrefix;
import std.regex : matchFirst;
import std.array : split;
import std.typecons : Tuple;
import std.file : exists, chdir, getcwd, dirEntries, SpanMode;

// using custom type for repo location that has built-in support for one directory.
// number of directories is not important, the custom type is.
// it protects us against unprocessed repo names
alias RepoLoc = Tuple!(string, string);

RepoLoc repoLocFromString(string name) {

  // try to match and drop possible .git extension
  // uses github character set without coercion (translating other characters to '-')
  // removes potentially leading root slash and surrounding quotes
  const auto re = `^(?:[ '"]*)(?:\/)?([a-zA-Z0-9_-][a-zA-Z0-9_.\/-]*)(?:\.git)?(?:[ '"]*)$`;
  auto match = matchFirst(name, re);
  if (match.empty()) {
    throw new Exception("repository name either empty or has invalid characters");
  }
  // split by posix path separators
  // this enforces uniform repository name interface
  auto spec = match[1];
  auto parts = split(spec, '/');
  string dir, repo;
  // handle different numbers of directories
  switch (parts.length) {
    case 1: dir = ""; repo = parts[0]; break;
    case 2: dir = parts[0]; repo = parts[1]; break;
    default: throw new Exception("trying to use too many directories");
  }
  // cop out on empty repository name
  if (name.length == 0) {
    throw new Exception("repository name empty");
  }

  // all good
  return RepoLoc(dir, repo);
}

string repoLocToPretty(RepoLoc loc) {
  if (loc[0] == "") {
    return loc[1] ~ ".git";
  } else {
    return loc[0] ~ "/" ~ loc[1] ~ ".git";
  }
}

// internally the paths are flattened so we don't have to create/remove folders
RepoLoc repoLocFromPath(string path) {
  auto chomped = chomp(chompPrefix(path, repoLocation), ".git");
  auto parts = split(chomped, "$");
  string dir, repo;
  switch (parts.length) {
    case 1: dir = ""; repo = parts[0]; break;
    case 2: dir = parts[0]; repo = parts[1]; break;
    default: throw new Exception("too many directories");
  }
  return RepoLoc(dir, repo);
}

/* returns actual path of repository */
string repoLocToPath(RepoLoc loc) {
  if (loc[0] == "") {
    return buildPath(repoLocation, loc[1] ~ ".git");
  } else {
    return buildPath(repoLocation, loc[0] ~ "$" ~ loc[1] ~ ".git");
  }
}

/* returns file path of repository config */
string repoLocToConfig(RepoLoc loc) {
  if (loc[0] == "") {
    return buildPath(configLocation, loc[1] ~ ".json");
  } else {
    return buildPath(configLocation, loc[0] ~ "$" ~ loc[1] ~ ".json");
  }
}

