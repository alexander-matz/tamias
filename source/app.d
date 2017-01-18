import std.stdio : writefln, writef, readln, File;
import std.string : indexOf, toLower, strip;
import std.format : format;
import std.process : environment, spawnProcess, pipeProcess, wait, Redirect;
import std.array : split, join;
import std.file : exists, chdir, getcwd, dirEntries, SpanMode;
import std.path : baseName, extension, buildPath, expandTilde, stripExtension;
import std.typecons : Tuple;

alias log = writefln;
alias getEnv = environment.get;

void msg(T...)(T a) {
  import std.stdio : stdout;
  stdout.writefln(a);
  stdout.flush();
}

void msgErr(T...)(T a) {
  import std.stdio : stderr;
  stderr.writefln(a);
  stderr.flush();
}

void enforcef(T...)(bool cond, T a) {
  import std.format : format;
  if (!cond) {
    throw new Exception(format(a));
  }
}

void failf(T...)(T a) {
  throw new Exception(format(a));
}

bool confirm(T...)(T a) {
  msg(format(a) ~ " [y/N]");
  auto answer = readln().strip();
  if (answer.toLower() == "y" || answer.toLower() == "yes") {
    return true;
  }
  return false;
}
/******************************************************************************
 * NAMES, VERSION, FILE PATHS
 */

const string appName = "tamias";
const string versionString = "v1.1.0";

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

/******************************************************************************
 * LOCKING/IPC etc
 *****************************************************************************/

File *lockfile = null;
void lockLock() {
  if (lockfile != null) {
    return;
  }
  lockfile = new File(lockfilePath(), "w");
  lockfile.lock();
}

void lockUnlock() {
  if (lockfile == null) {
    return;
  }
  lockfile.unlock();
  lockfile.close();
  delete lockfile;
  lockfile = null;
}

/******************************************************************************
 * REPO MANAGEMENT
 *****************************************************************************/

// using custom type for repo location that has built-in support for one directory.
// number of directories is not important, the custom type is.
// it protects us against unprocessed repo names
alias RepoLoc = Tuple!(string, string);

RepoLoc repoLocFromString(string name) {
  import std.regex : matchFirst;
  import std.array : split;

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
  import std.string : tr, chomp, chompPrefix;
  import std.array : split;
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

/******************************************************************************
 * Repo Configuration
 */

struct RepoConfig {
  string owner;
  string[] read;
  string[] write;
  string[] config;
};

// CONFIG + REPO MANIPULATION

RepoConfig repoConfigDefault(string username) {
  RepoConfig conf;
  conf.owner = username;
  conf.read = ["all"];
  conf.write = [];
  conf.config = [];
  return conf;
}

void repoSetConfig(RepoLoc loc, RepoConfig conf) {
  import std.json : JSONValue, toJSON;
  import std.file : write;

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
  import std.file : readText;
  import std.json : JSONValue, parseJSON;

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

/******************************************************************************
 * USER MANAGEMENT
 *****************************************************************************/

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
  import std.file : readText, isFile;
  import std.algorithm.sorting : sort;
  import std.array : split;

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

/******************************************************************************
 * REPO MANAGEMENT
 *****************************************************************************/

bool repoExists(RepoLoc loc) {
  return exists(repoLocToPath(loc));
}

void repoAdd(RepoLoc loc, RepoConfig conf) {
  import std.file : mkdir;

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
  import std.file : rmdirRecurse, remove;

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
  import std.file : dirEntries, SpanMode;
  import std.path : baseName, globMatch;
  RepoLoc[] result;
  foreach (repo; dirEntries(repoLocation, SpanMode.shallow)) {
    auto loc = repoLocFromPath(baseName(repo));
    auto pretty = repoLocToPretty(loc);
    if (pattern == "") {
      result ~= loc;
    } else if (globMatch(pretty, pattern)) {
      result ~= loc;
    }
  }
  return result;
}
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
 * SETUP + ADMIN
 *****************************************************************************/

// get username from keyfile
string userFromKeyfile(string keyfile) {
  import std.path : baseName, stripExtension;
  import std.string : lastIndexOf;

  string stripped = baseName(stripExtension(keyfile));
  auto pos = lastIndexOf(stripped, '@');
  if (pos > -1) {
    return stripped[0..pos];
  } else {
    return stripped;
  }
}

void install(string[] keyfiles) {
  import std.file : isFile, mkdir, copy, chdir, getcwd, thisExePath, write, append, preserveAttributesDefault;
  import std.format : format;
  import std.socket : Socket;
  import std.string : chomp;

  // Make sure key files exist (and make sure it's a .pub key)
  foreach (ref keyfile; keyfiles) {
    keyfile = chomp(keyfile, ".pub") ~ ".pub";
    enforcef(exists(keyfile) && isFile(keyfile), "key '%s' not found/not a file", keyfile);
  }

  // Confirm installation
  enforcef(confirm("install in '%s'?", baseLocation()), "aborted by user");

  // Ensure .ssh exists
  enforcef(exists(expandTilde("~/.ssh")), "~/.ssh does not exist, generate ssh key");

  foreach (path; [repoLocation(), configLocation(), keysLocation()]) {
    enforcef(!exists(path), "directory '%s' already exists", path);
  }

  msg("creating directories");
  if (!exists(baseLocation())) {
    mkdir(baseLocation());
  }
  foreach (path; [repoLocation(), configLocation()]) {
    mkdir(path);
  }

  const auto cwd = getcwd();

  const auto gitConfPath = buildPath(expandTilde("~"), ".gitconfig");
  msg("checking/fixing git credentials (%s)", gitConfPath);
  if (!exists(gitConfPath)) {
    write(gitConfPath, format("[user]\n"
                              "  email=%s@%s\n"
                              "  name=%s server", appName, Socket.hostName(), appName));
  }

  msg("creating keys and initializing repository");
  // add empty key repository
  const auto keysLoc = RepoLoc("", "keys");
  const auto keysBare = repoLocToPath(keysLoc);
  auto keysConf = repoConfigDefault("staff");
  keysConf.read = ["staff"];
  keysConf.write = ["staff"];
  keysConf.config = ["staff"];
  repoAdd(keysLoc, keysConf);
  execute(["git", "clone", keysBare, keysLocation()]);

  // add users for provided keys
  bool[string] seenUsers;
  foreach (keyfile; keyfiles) {
    // extract user from key file name
    string user = userFromKeyfile(keyfile);
    string keyfileName = baseName(keyfile);
    // if user starts with id_, this is not a legitimate user name
    // user "staff" as user in that case
    if (indexOf(user, "id_") == 0) {
      keyfileName = "staff@" ~ user ~ ".pub";
      user = "staff";
    }
    // actually copy key file
    copy(keyfile, buildPath(keysLocation(), keyfileName));
    // add role for this user (but not twice)
    if (user !in seenUsers) {
      seenUsers[user] = true;
      append(buildPath(keysLocation(), "users.conf"), user ~ " : staff");
    }
  }

  // commit and push keys
  chdir(keysLocation());
  execute(["git", "add", "-A"]);
  execute(["git", "commit", "-m", "initial keys"]);
  execute(["git", "push", "origin", "master"]);
  chdir(cwd);

  msg("copying binaries");
  mkdir(binLocation());
  copy(thisExePath(), appShellPath());
  // !! PLATFORM DEPENDEND !! CALLS UNIX ONLY CHMOD COMMAND
  execute(["chmod", "ugo+x", appShellPath()]);

  updateKeys();
}

////////////////////////////////////////////
void updateKeys() {
  import std.file : readText, write;
  import std.string : lastIndexOf;

  string[] keyfiles;
  string cwd = getcwd();

  chdir(keysLocation());
  qexecute(["git", "pull"]);
  chdir(cwd);

  foreach (file; dirEntries(keysLocation(), SpanMode.shallow)) {
    string base = baseName(file);
    if (extension(base) == ".pub") {
      keyfiles ~= [base];
    }
  }
  string[] lines;
  foreach (keyfile; keyfiles) {
    string user = userFromKeyfile(keyfile);
    const string key = readText(buildPath(keysLocation, keyfile)).strip();
    const string sshOpts = "no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty";
    lines ~= [format("command=\"%s %s\",%s %s\n", appShellPath(), user, sshOpts, key)];
  }
  write(authorizedKeys(), lines.join());
}

/******************************************************************************
 * GIT COMMANDS
 *****************************************************************************/

void execute(string[] cmdline) {
  auto pid = spawnProcess(cmdline);
  auto res = wait(pid);
  enforcef(res == 0, "return '%s' returned code %d", join(cmdline, ' '), res);
}

void qexecute(string[] cmdline) {
  auto pipes = pipeProcess(cmdline, Redirect.stdout | Redirect.stderr | Redirect.stdin);
  auto res = wait(pipes.pid);
  enforcef(res == 0, "return '%s' returned code %d", join(cmdline, ' '), res);
}

string[] sexecute(string[] cmdline, string dir = ".") {
  import std.process : Config;
  auto pipes = pipeProcess(cmdline, Redirect.stdout | Redirect.stderr | Redirect.stdin,
      null, Config.none, dir);
  string[] output;
  foreach (line; pipes.stdout.byLine) output ~= line.idup;
  auto res = wait(pipes.pid);
  enforcef(res == 0, "'%s' returned code %d", join(cmdline, ' '), res);
  return output;
}

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
  msg("  list                 print repository available to you");
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
        msg("roles: %s", join(user.roles, ","));
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
    msg("error: %s", e.msg);
    return 1;
  }
  return 0;
}
