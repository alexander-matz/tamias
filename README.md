# What is Tamias?

Tiamias is a git server much like gitolite aimed at small to (maybe) medium teams.
Its goal is to make repository creation and destruction as easy as possible as well
as be completely configurable through the commandline with configuration being
located in repositories kept to a minimum.
Its architecture is heavily inspired by gitolite.

# Why, though?

I'm an avid fan of simple git solutions like gitolite but found myself frustrated
by having to go through the following workflow just to create a temporary repository:

- `$ git clone git@myserver:gitolite-admin`
- start up an editor with gitolite-admin/conf/gitolite.conf
- modifying that file according to its format to add/remove a repository
- save
- `$ git add -u`
- `$ git commit`
- `$ git push origin master`

Even though it does not seem like much, my opinion is that every additional step in
achieving something discourages users to go through the process.
So adding a repository in tamias is achieved by executing:

`$ ssh git@myserver add <repository>`

Deleting a repository requires executing:

`$ ssh git@myserver rm <repository>`

# Installation

Create a user that acts as your git user.
Be aware that regular ssh access will not be possible after installation of tamias.
After that build a release version of the tamias sources on your server by executing:

`$ dub build --build=release`

Then execute `./tamias install <ssh-key> [ssh-keys...]` on the server.

It is helpful to supply keys with filenames following the format explained in section
'Adding/removing users' so you start with a reasonable configuration of users and
permissions.

# Usage

In addition to the regular git operations clone/pull/fetch/push etc. some additional
ssh commands are available.
They are used like they would be executables on the server.
So you would execute the command 'list' by executing `ssh git@myserver list`.
The following commands are available:

- `version`
- `list`
- `add <repository>`
- `rm <repository>`
- `config <repository> [update ...]`
- `whoami`

# Access control

Access control is kept simple, the only thing that controls what you're able to access
are your roles.
A role is a simpler version of posix groups with mostly the same semantics.
Every user is assuming a number of different roles as well as a few special ones.
The special ones are a role that is the name as their username as well as the role 'all'.

A repository has a list for each of the permissions 'read', 'write', 'config'.
'read' and 'write' are straight forward and just determine who can pull/push a
repository.
The 'config' permission allows to modify the values for the owner, read, write, and config
permissions.

The role 'staff' is special in that is effectively the tamias equivalent of a 'root' user
that has all permissions.

The same holds true for the owner of a repository.

## Adding/removing users

Since actual usernames are ignored except when looking up ownership of a repository,
creating a user does not require a lot of work.
On updating the 'keys.git' repositories users are recreated as it is looking for
public keys with the extension '.pub'.
Naming conventions follows the same conventions as gitolite does:

- key files named `...@<user>.pub` user the part after the last '@' as the username
- if there is no '@' in the filename of the key, everything before the '.pub' is considered the username

## Configuring user roles

Users with write access to the special 'keys.git' repository can modify the roles users
assume.
In addition to the default roles for users (username + 'all'), roles are specified in the
file 'users.conf' in the 'keys.git' repository.
It follows a simple format:

`username : role1 role2 role3 ...`

Whitespaces are used to separate roles from another. Allowed characters for roles are
alphanumeric characters, underscore, and dash.

## Configuring access permissions

If you're either the owner of a repository, have 'config' permission or are 'staff', you
can modify the access permissions of a repository.

The general syntax, as mentioned above is:

`config <repository> [update1 ...]`

If no updates are supplied, the current configuration is printed.
Multiple updates can be supplied by seperating them by whitespaces.

An update can either update the owner or one of the permissions.
If you're updating the owner, the following syntax is enforced:

`owner=<new-owner>`

If you update a permission you can either add/remove or set the roles for that permission.
In either case you can pass multiple users separated by commas.
It's explained the most easy way by some examples:

- Adding the roles 'all' and 'deimos' to roles that can write: `config <repo> write+all,deimos`
- Disallowing 'all' to read the repository: `config <repo> read-all`
- Only allowing 'staff' config access, removing everybody else: `config <repo> config=staff`
