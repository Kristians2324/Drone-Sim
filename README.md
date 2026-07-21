# Drone Sim Monorepo

This repository contains multiple projects collected under a single workspace:

- Godot-drone-master/
- MavLink/

What I did:
- Initialized a git repository at the workspace root and committed a snapshot (branch `monorepo-init`).
- Added a `.gitignore` customized for Godot and development files.

Recommended next steps to preserve existing remote repositories (choose one):

1) Add existing repos as git submodules (keeps separate histories and remotes):

```bash
# from the workspace root
# example: add the Godot project as a submodule (replace URL with the project's remote)
git submodule add <GODOT_REMOTE_URL> Godot-drone-master
git submodule add <MAVLINK_REMOTE_URL> MavLink
git commit -m "Add submodules for Godot and MavLink"
```

2) Import remote history into subdirectories using `git subtree` (combines history into this monorepo):

```bash
# add remote and pull into a subdirectory
git remote add godot <GODOT_REMOTE_URL>
git fetch godot
git subtree add --prefix=Godot-drone-master godot main --squash
```

3) Keep the workspace as a single repo (what I committed) and push this monorepo to a new remote:

```bash
git remote add origin <NEW_MONOREPO_URL>
git push -u origin monorepo-init
```

If you want, I can:
- Add real submodules using the remote URLs (provide them or I can try to detect),
- Convert specified remotes into `git subtree` histories,
- Push this monorepo to a remote you provide.

Tell me which option you prefer and I will do it automatically.
