import tamias.config;
import tamias.setup;
import tamias.util;
import tamias.repoloc;
import tamias.repo;
import tamias.user;

import std.string : split;
import std.format : format;
import std.array : join;
import std.process : environment, spawnProcess, wait;

/******************************************************************************
 * CONFIGURATION INTERFACE
 *****************************************************************************/

string[] parseOption(string txt) {
  import std.regex : matchAll;
  const auto re = `\s*([a-zA-Z0-9_.-]+)([-+=])([a-zA-Z0-9_.,-]*)`;
  auto m = matchAll(txt, re);
  if (m.empty()) {
    throw new Exception("invalid format");
  }
  auto cap = m.captures();
  return [cap[1], cap[2], cap[3]];
}

string[] arrayAddUnique(string)(string[] s, string[] t) {
  import std.algorithm: canFind;
  string[] result;
  foreach (string c; s)
    if (!result.canFind(c))
      result ~= c;
  foreach (string c; t)
    if (!result.canFind(c))
      result ~= c;
  return result;
}

string[] arrayRemove(string)(string[] s, string[] t) {
  import std.algorithm: canFind;
  string[] result;
  foreach (string c; s) {
    if (!t.canFind(c)) {
      result ~= c;
    }
  }
  return result;
}

string[] arraySetUnique(string[] s) {
  import std.algorithm: canFind;
  string[] result;
  foreach (string c; s)
    if (!result.canFind(c))
      result ~= c;
  return result;
}

string[] arrayUpdate(string[] s, string op, string[] t) {
    switch (op) {
      case "+":
        return arrayAddUnique(s, t);
      case "=":
        return arraySetUnique(t);
      case "-":
        return arrayRemove(s, t);
      default:
        failf("invalid array operand: %s", op);
    }
    return [];
}

RepoConfig repoConfigUpdateFromOption(RepoConfig conf, string option) {
  import std.string : toLower;
  RepoConfig updated = conf;
  auto parsed = parseOption(option);
  switch (parsed[0]) {
    case "owner":
      enforcef(parsed[1] == "=", "can only assign owner, not add or remove");
      enforcef(confirm("really change owner?"), "aborted by user");
      conf.owner = parsed[2];
      break;
    case "read":
      auto users = (split(parsed[2], ","));
      conf.read = arrayUpdate(conf.read, parsed[1], users);
      break;
    case "write":
      auto users = (split(parsed[2], ","));
      conf.write = arrayUpdate(conf.write, parsed[1], users);
      break;
    case "config":
      auto users = (split(parsed[2], ","));
      conf.config = arrayUpdate(conf.config, parsed[1], users);
      break;
    default:
      failf("not an option: %s", parsed[0]);
  }
  return conf;
}

/******************************************************************************
 * GIT COMMANDS
 *****************************************************************************/

void gitCommand(string op, RepoLoc loc) {
  auto path = repoLocToPath(loc);
  auto pid = spawnProcess([op, path]);
  auto res = wait(pid);
  enforcef(res == 0, "return '%s' returned code %d", op ~ " " ~ path, res);
}

void help() {
  msg("usage:");
  msg("  %s command [arguments]", appName);
  msg("");
  msg("commands:");
  msg("  --- local+ssh commands ---");
  msg("  version              print version number");
  msg("  whoami               print user name and roles");
  msg("  list [filter]        print repository available to you");
  msg("  add <repository>     add new repository");
  msg("  rm <repository>      remove existing repository");
  msg("  config <repository> [settings...");
  msg("                       update repository settings, example:");
  msg("                       config myrepo write+staff read=all config-myuser");
  msg("  --- local only commands ---");
  msg("  install <keyfile..>  install tamias using provided key"); 
  msg("  update-keys          invoke manual key update");
  msg("  --- ssh only commands ---");
  msg("  git-upload-pack,");
  msg("  git-upload-archive,");
  msg("  git-receive-pack     git internal commands implementing clone/push/pull etc.");
}

int main(string[] args) {
  alias getEnv = environment.get;
  bool isLocal;
  string[] command;
  string username;
  if (getEnv("SSH_CONNECTION", "") != "") {
    // called from ssh, retrieve user from command line
    // and command from environment variable
    command = split(getEnv("SSH_ORIGINAL_COMMAND", ""));
    username = args[1];
    isLocal = false;
  } else {
    // called from command line, retrieve user from env
    // and command from command line
    command = args[1..$];
    username = getEnv("USER", "nobody");
    if (getEnv("NOSTAFF", "") == "") {
      isLocal = true;
    }
  }

  if (command.length < 1) {
    msg("error: no command specified");
    help();
    return 1;
  }


  // in case we're locking, unlock on exit. function checks whether lock was acquired
  scope(exit) lockUnlock();
  try {
    User user;
    try {
      user = userRead(username, isLocal);
    } catch (Exception e) {
      msgErr("warning: %s, using defaults", e.msg);
      user = userDefault(username, isLocal);
    }
    // command dispatcher
    switch (command[0]) {
      case "version":
        msg(buildString);
        break;
      case "list":
        lockLock();
        enforcef(command.length <= 2, "usage: list [pattern]");
        auto pattern = "";
        if (command.length > 1) {
          pattern = command[1];
        }
        auto list = repoList(pattern);
        if (list.length == 0) {
          msg("no available repositories");
          break;
        }
        foreach (loc; list) {
          auto conf = repoGetConfig(loc);
          if (canRead(conf, user)) {
            auto path = repoLocToPath(loc);
            string info;
            try {
              info = sexecute(["git", "show", "-s", "--format=%h @ %cr - %s", "HEAD"], path)[0];
            } catch (Exception e) {
              info = "no commits";
            }
            msg("%s", repoLocToPretty(loc));
            msg("  owner: %s", conf.owner);
            msg("  commit: %s", info);
            string[] rights = ["read"];
            if (canWrite(conf, user)) rights ~= "write";
            if (canConfig(conf, user)) rights ~= "config";
            msg("  rights: %s", join(rights, ","));
          }
        }
        break;
      case "add":
        lockLock();
        enforcef(command.length == 2, "usage: add <repository>");
        auto loc = repoLocFromString(command[1]);
        auto conf = repoConfigDefault(user.name);
        repoAdd(loc, conf);
        break;
      case "rm":
        lockLock();
        enforcef(command.length >= 2, "usage: rm <repository> [repositories...]");
        auto loc = repoLocFromString(command[1]);
        auto conf = repoGetConfig(loc);
        enforcef(canConfig(conf, user), "insufficient permissions");
        repoRemove(loc);
        break;
      case "config":
        lockLock();
        enforcef(command.length >= 2, "usage: config <repository> [settings...]");
        auto loc = repoLocFromString(command[1]);
        auto conf = repoGetConfig(loc);
        enforcef(canConfig(conf, user), "insufficient permissions");
        auto settings = command[2..$];
        foreach (setting; settings) {
          conf = repoConfigUpdateFromOption(conf, setting);
        }
        repoSetConfig(loc, conf);
        msg("configuration of %s:", repoLocToPretty(loc));
        msg("  owner:  %s", conf.owner);
        msg("  read:   %s", join(conf.read, ","));
        msg("  write:  %s", join(conf.write, ","));
        msg("  config: %s", join(conf.config, ","));
        break;
      case "whoami":
        enforcef(command.length == 1, "usage: whoami");
        msg("username: %s", user.name);
        msg("roles: %s", join(user.roles, ", "));
        break;
      case "install":
        enforcef(isLocal, "installation only from local command line");
        enforcef(command.length >= 2, "usage: install <keyfile..>");
        install(command[1..$]);
        break;
      case "update-keys":
        lockLock();
        enforcef(command.length == 1, "usage: updatekeys");
        enforcef(isLocal, "manual key update only from local command line");
        updateKeys();
        break;
      // upload-pack + upload-archive are read accesses
      case "git-upload-pack":
      case "git-upload-archive":
        lockLock();
        try {
          enforcef(!isLocal, "git commands only via ssh");
          enforcef(command.length == 2, "command expects an argument");
          auto loc = repoLocFromString(command[1]);
          auto conf = repoGetConfig(loc);
          // no read access, so dont hand out information about existence
          enforcef(repoExists(loc), "insufficient permissions or not a repository");
          enforcef(canRead(conf, user), "insufficient permissions or not a repository");
          gitCommand(command[0], loc);
        } catch (Exception e) {
          msgErr("error: %s", e.msg);
        }
        break;
      // receive-pack is write access
      case "git-receive-pack":
        lockLock();
        try {
          enforcef(!isLocal, "git commands only via ssh");
          enforcef(command.length == 2, "command expects an argument");
          auto loc = repoLocFromString(command[1]);
          auto conf = repoGetConfig(loc);

          enforcef(repoExists(loc), "insufficient permissions or not a repository");
          enforcef(canRead(conf, user), "insufficient permissions or not a repository");
          enforcef(canWrite(conf, user), "insufficient permissions");
          gitCommand(command[0], loc);
          // trigger key update if keys repository is uploaded
          if (loc[0] == "" && loc[1] == "keys") {
            msgErr("update keys");
            updateKeys();
          }
        } catch (Exception e) {
          msgErr("error: %s", e.msg);
        }
        break;
      case "help":
        help();
        break;
      default:
        throw new Exception(format("unsupported command '%s', try '%s help'", command[0], appName));
    }
  } catch (Exception e) {
    msgErr("error: %s", e.msg);
    return 1;
  }
  return 0;
}
