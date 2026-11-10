# Game Project

A starter project for building a game with Godot 4. The game concept and mechanics can be added once they are defined.

## Open the project

1. Install Godot 4.3 or newer.
2. In Godot's Project Manager, choose **Import** and select this folder's `project.godot` file.
3. Press **F6** to run the current scene or **F5** to run the project.

The starter scene is `scenes/main.tscn`; its script is `scripts/main.gd`. Put original art, audio, and other assets in `assets/`.

## Next step

Describe the game you want to make in Codex. Include anything you already know about the genre, player actions, camera, art style, platform, and what a first playable version should contain. It's fine to start with only a rough idea. The project can then be built out in small playable steps.

## Git and GitHub

This folder is initialized as a local Git repository. To publish it, create an empty repository on GitHub, then from this folder run:

```sh
git remote add origin https://github.com/YOUR-USER/YOUR-REPOSITORY.git
git add .
git commit -m "Create Godot starter project"
git branch -M main
git push -u origin main
```

Replace the URL with the repository address. GitHub authentication can be handled by Git Credential Manager or `gh auth login` if GitHub CLI is installed.
