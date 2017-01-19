module tamias.setup;

import tamias.config;
import tamias.util;
import tamias.repoloc;
import tamias.repo;

import std.path : baseName, stripExtension, extension;
import std.string : lastIndexOf, chomp;
import std.file : isFile, mkdir, copy, chdir, getcwd, thisExePath, readText, write, append, preserveAttributesDefault;
import std.format : format;
import std.socket : Socket;

// get username from keyfile
string userFromKeyfile(string keyfile) {
  string stripped = baseName(stripExtension(keyfile));
  auto pos = lastIndexOf(stripped, '@');
  if (pos > -1) {
    return stripped[0..pos];
  } else {
    return stripped;
  }
}

void install(string[] keyfiles) {

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
      append(buildPath(keysLocation(), "users.conf"), user ~ " : staff\n");
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

// pull local key repository, transfer keys into authorizedkeys file
void updateKeys() {

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
