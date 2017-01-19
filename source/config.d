module tamias.config;

import std.string : format;
import std.path : buildPath, expandTilde;

const string appName = "tamias";
const string versionString = "v1.1.1";

debug {
  const string buildType = "debug";
} else {
  const string buildType = "release";
}

string buildString = format("%s-%s-%s", appName, versionString, buildType);

debug {
  string baseLocation() { return buildPath(".", "test"); }
  string authorizedKeys() { return buildPath(".", "test" , "authorized_keys"); }
  string lockfilePath() { return buildPath(".", "." ~ appName ~ ".lock"); }
} else {
  string baseLocation() { return buildPath(expandTilde("~")); }
  string authorizedKeys() { return buildPath(expandTilde("~"), ".ssh", "authorized_keys"); }
  string lockfilePath() { return buildPath(expandTilde("~"), "." ~ appName ~ ".lock"); }
}

string binLocation() { return buildPath(baseLocation(), "bin"); }
string repoLocation() { return buildPath(baseLocation(), "repos"); }
string configLocation() { return buildPath(baseLocation(), "config"); }
string keysLocation() { return buildPath(baseLocation(), "keys"); }

string appShellPath() { return buildPath(binLocation(), appName ~ "-shell"); }
string userConfPath() { return buildPath(keysLocation(), "users.conf"); }

