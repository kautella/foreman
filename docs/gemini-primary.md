# Gemini CLI primary setup

Gemini runs Firstmate's primary hooks from the user's Gemini settings because Gemini CLI 0.66.0 accepts system settings only from a root-owned location.
Do not add these hooks to a project's `.gemini/settings.json`.

Replace `/absolute/path/to/firstmate` below with the physical path of this checkout and merge the entries into `~/.gemini/settings.json`.

```json
{
  "hooks": {
    "BeforeAgent": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/firstmate/bin/fm-gemini-primary-hook.sh before"
          }
        ]
      }
    ],
    "AfterAgent": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/firstmate/bin/fm-gemini-primary-hook.sh after"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/firstmate/bin/fm-gemini-primary-hook.sh session-end"
          }
        ]
      }
    ]
  }
}
```

Start `gemini` from the Firstmate checkout.
Every hook verifies the Gemini payload's physical current directory before it does anything, so this user-level configuration is inert in every other project.

The `BeforeAgent` hook supplies the initial Firstmate context.
The `AfterAgent` hook waits only while Firstmate has work that needs attention.
When that work needs a response, it exits with Gemini's retry status and supplies the watcher result as the next turn's context.

Use a Gemini CLI version with command hooks and exit-2 retry-turn support, and verify the integration on the target host before relying on it for active work.
