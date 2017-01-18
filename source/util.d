module tamias.util;

import tamias.config;

import std.stdio : File, stdout, stderr, readln;
import std.string : strip, toLower, indexOf;
import std.format : format;
import std.process : spawnProcess, pipeProcess, wait, Redirect, Config;
import std.array : join;

void msg(T...)(T a) {
  stdout.writefln(a);
  stdout.flush();
}

void msgErr(T...)(T a) {
  stderr.writefln(a);
  stderr.flush();
}

void enforcef(T...)(bool cond, T a) {
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
  auto pipes = pipeProcess(cmdline, Redirect.stdout | Redirect.stderr | Redirect.stdin,
      null, Config.none, dir);
  string[] output;
  foreach (line; pipes.stdout.byLine) output ~= line.idup;
  auto res = wait(pipes.pid);
  enforcef(res == 0, "'%s' returned code %d", join(cmdline, ' '), res);
  return output;
}
