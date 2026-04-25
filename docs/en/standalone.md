# Standalone Configuration

The Standalone version of the project is designed for distributing a single game, making it ideal for platforms like Steam or for creating a Web version that loads a specific game automatically.

## Changing the Game Path

To change which game the standalone version boots, follow these steps:

### Editor Overview

The image below shows the Godot Editor setup for the Standalone scene:

![Changing the game path in Standalone version](../images/change_path_game.png)

**What you see in the image:**

1.  **Scene Tree**: The `Main48K_Standalone.tscn` (or `Main128K_Standalone.tscn`) is open.
2.  **Selected Node**: The root node (**Main48K_Standalone**) is selected.
3.  **Inspector**: On the right panel, under the **Standalone Configuration** category, you find the game configuration fields.
4.  **Game Path**: Here you define the path to the local game file (e.g., `res://games/znake.tap`).

!!! tip
    Make sure the selected game file is located within the `res://` project folder (e.g., inside `res://games/`) to ensure it is correctly included in the final executable.

---

## Web Autoload (Dynamic Loading)

This feature is ideal for the Web, allowing you to swap games on the server without having to export the project again.

### File Structure on the Server

As shown in the image below, for autoload to work, the game file must be in the same folder as the exported Godot files:

![Files Autoload Project](../images/files_autoload_project.png)

*   **Main File**: The game file must be named exactly **`autoload.tap`**.
*   **Location**: It must be at the root of the server, next to `index.html` and `index.pck`.
*   **Server**: The `server.py` file must be present to run the local server with the correct permissions.

### How to Enable in Godot

In the Inspector, you can toggle between local and web mode:

![Enable Web Autoload](../images/enable_autoload.png)

1.  **Enable Web Autoload**: Click the **Web Autoload** checkbox.
2.  **Automatic Effect**: As soon as you enable this option, the *Game Path* field disappears and is cleared automatically. This ensures the emulator prioritizes the `autoload.tap` file found on the server.

---

## Web Server for Testing (Python)

Due to modern browser security policies, you must use the included Python server for testing autoload:

```bash
# Command to start the server in the build/web folder
python server.py --port 8060 --root .
```

---

## Troubleshooting: Clearing Cache in Chrome

If you update the `autoload.tap` file on the server but the browser continues to load the old game, you must force a cache clear:

![Empty Cache and Hard Reload](../images/force_clear_cache.png)

1.  Open the game in the browser and press **F12**.
2.  With the F12 window open, **RIGHT-CLICK** the **Refresh/Reload** icon.
3.  Select the option: **"Empty cache and hard reload"**.

!!! tip
    If the problem persists, change the port in the server command (e.g., `--port 8070`) to force the browser to treat the site as new.
