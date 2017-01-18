module tamias.user;

import tamias.config;
import tamias.util;
import tamias.repo;

import std.file : readText, isFile;
import std.algorithm.sorting : sort;
import std.array : split;
import std.string : strip;

struct User {
  string name;
  string[] roles;
};

User userDefault(string username, bool isLocal) {
  User user;
  user.name = username;
  user.roles ~= username;
  user.roles ~= "all";
  if (isLocal) {
    user.roles ~= "staff";
  }
  return user;
}

User userRead(string username, bool isLocal) {
  User user = userDefault(username, isLocal);

  // return default user without complaining if no config exists
  if (!exists(userConfPath)) {
    return user;
  }

  auto lineNo = 0;
  string[] roles;
  foreach (line; split(readText(userConfPath), '\n')) {
    lineNo = lineNo + 1;
    line = line.strip();
    if (line == "") continue;

    auto sides = split(line, ':');
    enforcef(sides.length == 2, "malformed line '%d' in users.conf", lineNo);
    auto name = sides[0].strip();

    // abort if different user
    if (name != username) continue;

    foreach (role; split(sides[1])) {
        roles ~= role.strip();
    }
    break;
  }
  sort(roles);
  foreach(role; roles) {
    if (user.roles.length == 0 || user.roles[$-1] != role) {
      user.roles ~= role;
    }
  }
  return user;
}

bool hasRight(string username, string[] roles, string owner, string[] perms) {
  if (username == owner) {
    return true;
  }
  foreach (role; roles) {
      if (role == "staff") {
        return true;
      }
  }
  foreach (perm; perms) {
    foreach (role; roles) {
      if (perm == role) {
        return true;
      }
    }
  }
  return false;
}

bool canRead(RepoConfig config, User user) {
  return hasRight(user.name, user.roles, config.owner, config.read);
}

bool canWrite(RepoConfig config, User user) {
  return hasRight(user.name, user.roles, config.owner, config.write);
}

bool canConfig(RepoConfig config, User user) {
  return hasRight(user.name, user.roles, config.owner, config.config);
}

