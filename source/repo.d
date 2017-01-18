module tamias.repo;

import tamias.config;
import tamias.repoloc;
import tamias.util;

import std.file : exists, mkdir, rmdirRecurse, mkdirRecurse, remove, dirEntries, SpanMode, write, readText;
import std.path : baseName;
import std.string : indexOf;
import std.algorithm.sorting : sort;
import std.json : JSONValue, toJSON, parseJSON;

struct RepoConfig {
  string owner;
  string[] read;
  string[] write;
  string[] config;
};

RepoConfig repoConfigDefault(string username) {
  RepoConfig conf;
  conf.owner = username;
  conf.read = ["all"];
  conf.write = [];
  conf.config = [];
  return conf;
}

void repoSetConfig(RepoLoc loc, RepoConfig conf) {
  enforcef(repoExists(loc), "not a repository: %s", repoLocToPretty(loc));
  const auto path = repoLocToConfig(loc);
  JSONValue jj;
  jj["owner"] = JSONValue(conf.owner);
  jj["read"] = JSONValue(conf.read);
  jj["write"] = JSONValue(conf.write);
  jj["config"] = JSONValue(conf.config);

  write(path, toJSON(&jj, true));
}

RepoConfig repoGetConfig(RepoLoc loc) {
  enforcef(repoExists(loc), "not a repository: %s", repoLocToPretty(loc));
  const auto path = repoLocToConfig(loc);
  const string contents = readText(path);
  JSONValue jj = parseJSON(contents);

  RepoConfig conf;
  conf.owner = jj["owner"].str;
  conf.read = [];
  foreach (readAcc; jj["read"].array) {
    conf.read ~= readAcc.str;
  }
  conf.write = [];
  foreach (writeAcc; jj["write"].array) {
    conf.write ~= writeAcc.str;
  }
  conf.config = [];
  foreach (configAcc; jj["config"].array) {
    conf.config ~= configAcc.str;
  }

  return conf;
}

bool repoExists(RepoLoc loc) {
  return exists(repoLocToPath(loc));
}

void repoAdd(RepoLoc loc, RepoConfig conf) {
  const auto pretty = repoLocToPretty(loc);

  enforcef(!repoExists(loc), "repository %s does already exist", pretty);
  const auto barePath = repoLocToPath(loc);
  try {
    mkdir(barePath);
    qexecute(["git", "init", "--bare", barePath]);
    repoSetConfig(loc, conf);
  } catch (Exception e) {
    failf("error initializing repository %s", pretty);
  }
  msg("initialized empty repository %s", pretty);
}

void repoRemove(RepoLoc loc) {
  const auto pretty = repoLocToPretty(loc);

  enforcef(repoExists(loc), "not a repository: %s", repoLocToPretty(loc));
  enforcef(confirm("really delete repository '%s'?", pretty), "aborted by user");

  try {
  const auto barePath = repoLocToPath(loc);
  rmdirRecurse(barePath);
  const auto confPath = repoLocToConfig(loc);
  remove(confPath);
  } catch (Exception e) {
    failf("error removing repository %s", pretty);
  }
  msg("removed repository %s", pretty);
}

RepoLoc[] repoList(string pattern) {
  RepoLoc[] result;
  foreach (repo; dirEntries(repoLocation, SpanMode.shallow)) {
    auto loc = repoLocFromPath(baseName(repo));
    auto pretty = repoLocToPretty(loc);
    if (pattern == "") {
      result ~= loc;
    } else if (indexOf(pretty, pattern) != -1) {
      result ~= loc;
    }
  }
  sort(result);
  return result;
}
