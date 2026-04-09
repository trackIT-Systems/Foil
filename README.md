# Foil

Foil is a small macOS companion for [Plane](https://plane.so): capture work items from anywhere with a global shortcut and a quick floating panel, without leaving what you are doing.

## Features

- **Quick capture** — Open a compact panel (global shortcut, configurable; default is ⌥ Space) to create a Plane work item with title, description, project, and optional fields such as state, assignees, labels, parent item, cycle, modules, dates, estimate, and draft mode.
- **Plane Cloud or self-hosted** — Point the app at the Plane API base URL you use (for example `https://api.plane.so` or your own instance).
- **Runs quietly** — Optional Dock icon, optional menu bar item, and optional “Open at login” (managed in System Settings when macOS asks for approval).

## Requirements

- macOS **26.3** or later.
- Xcode **26** (or compatible) to build from source.
- A Plane workspace and a **personal access token** (Plane: *Preferences → Personal access tokens*).

## Setup

1. Build and run the app, or open the release build if you use one.
2. On first launch, enter:
   - **API base URL** — e.g. `https://api.plane.so`, or your self-hosted API root.
   - **Workspace slug** — the slug of your Plane workspace.
   - **Access token** — paste your personal access token.
3. Adjust **Settings** for Dock / menu bar presence, **Open at login**, and the **quick capture** shortcut.

You can close the main window; Foil keeps running in the background while configured.

## Building from source

```bash
open Foil.xcodeproj
```

Select the **Foil** scheme, choose **My Mac**, then **Product → Run** (⌘R) or **Archive** for distribution.

## Development

This app was created using agentic coding in [Cursor](https://cursor.com) and **Composer 2**.

## License

This project is licensed under the **GNU General Public License v3.0** — see [LICENCE](LICENCE).

## Trademark note

“Plane” is a trademark of its respective owners. Foil is an independent project and is not affiliated with or endorsed by Plane.
