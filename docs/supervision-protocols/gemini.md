<!-- fm:supervision-protocol:v1 harness=gemini -->
Mode: Gemini AfterAgent-hook-owned supervision.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
   After handling all emitted wakes and reconciling open decisions and unread status lines, run the exact `--ack-through` command printed as `WAKE_ACK_REQUIRED`.
2. Configure the documented guarded user-level Gemini hooks before starting the primary.
   They own Gemini's BeforeAgent, AfterAgent, and SessionEnd hooks and stand down unless the hook payload's current directory is this Firstmate home.
3. Every normal AfterAgent boundary that still needs supervision waits on one home-scoped watcher cycle.
   An actionable close exits the hook with Gemini's retry status and delivers the watcher result as the next handling turn.
4. On that handling turn, drain first and handle the result.
   Do not run `bin/fm-watch-arm.sh` after an ordinary wake; the next normal turn end parks again automatically.
5. The retry turn's `stop_hook_active` flag prevents the hook from parking that handling turn again.
   After its response ends normally, the following captain turn resumes automatic parking.
6. A watcher-start failure is delivered as a retry turn with the startup result.
   Inspect the failure rather than starting a manual watcher loop.
7. Waiting on the hook-owned cycle is silent.

The watcher remains `bin/fm-watch.sh`, and the primary hook uses `bin/fm-watch-arm.sh` as its verified arm wrapper.
