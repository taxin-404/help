#!/usr/bin/env python3
"""
TeraBox Sync TUI — view sync history and failures, trigger retries.

Reads logs written by terabox-sync.sh:
  ~/.local/share/terabox-sync/sync.log
  ~/.local/share/terabox-sync/failed.log

Requires: pip install textual --break-system-packages
"""

import os
import subprocess
import re
from pathlib import Path

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Header, Footer, Static, DataTable, Log
from textual.reactive import reactive
from textual.worker import Worker, get_current_worker

LOG_DIR = Path.home() / ".local/share/terabox-sync"
SYNC_LOG = LOG_DIR / "sync.log"
FAILED_LOG = LOG_DIR / "failed.log"
SYNC_SCRIPT = Path(
    os.environ.get("SYNC_SCRIPT", Path.home() / ".config/cloud-sync/scripts/terabox-sync.sh")
)

# Matches both old and new sync script formats
STATUS_RE = re.compile(
    r"^\[(.+?)\] "
    r"(?:"
    r"Sync clean, no errors\."
    r"|Sync had (\d+) error\(s\).*"
    r"|Sync FAILED(?:[^\d]*)(\d*) error\(s\).*"
    r"|bisync exited with code (\d+)"
    r")"
)
FAIL_HEADER_RE = re.compile(r"^----- (.+) -----")


def parse_sync_runs(text: str):
    """Return list of (timestamp, status, error_count) newest first."""
    runs = []
    for line in text.splitlines():
        m = STATUS_RE.match(line)
        if m:
            ts = m.group(1)
            had_errors = m.group(2) or m.group(3)
            exit_code = m.group(4)
            if "clean" in line:
                runs.append((ts, "OK", 0))
            elif had_errors:
                runs.append((ts, "FAILED", int(had_errors)))
            elif exit_code:
                runs.append((ts, "FAILED", 0))
            else:
                runs.append((ts, "FAILED", 0))
    runs.reverse()
    return runs


def parse_failures(text: str):
    """Return list of (timestamp, error_line) newest first."""
    failures = []
    current_ts = None
    for line in text.splitlines():
        m = FAIL_HEADER_RE.match(line)
        if m:
            current_ts = m.group(1)
            continue
        if line.strip() and current_ts:
            failures.append((current_ts, line.strip()))
    failures.reverse()
    return failures


class StatusBar(Static):
    """Shows last run status at a glance."""

    status_text = reactive("Loading...")

    def render(self) -> str:
        return self.status_text


class TeraboxTUI(App):
    CSS = """
    Screen {
        layout: vertical;
    }
    #top {
        height: auto;
        padding: 1 2;
        background: $panel;
    }
    #body {
        height: 1fr;
    }
    #runs_table {
        width: 40%;
        border: solid $primary;
    }
    #failures_panel {
        width: 60%;
        border: solid $error;
    }
    Button {
        margin: 1 2;
    }
    """

    BINDINGS = [
        ("r", "retry_sync", "Retry sync now"),
        ("f", "refresh_logs", "Refresh"),
        ("q", "quit", "Quit"),
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield StatusBar(id="statusbar")
        with Horizontal(id="body"):
            yield DataTable(id="runs_table")
            with Vertical(id="failures_panel"):
                yield Static("Recent Failures", id="failures_title")
                yield Log(id="failures_log", auto_scroll=False)
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#runs_table", DataTable)
        table.add_columns("Time", "Status", "Errors")
        table.cursor_type = "row"
        self.refresh_data()
        self._refresh_timer = self.set_interval(30, self.refresh_data)

    def refresh_data(self) -> None:
        statusbar = self.query_one("#statusbar", StatusBar)
        table = self.query_one("#runs_table", DataTable)
        failures_log = self.query_one("#failures_log", Log)

        table.clear()
        failures_log.clear()

        # Handle sync.log
        if not SYNC_LOG.exists():
            statusbar.status_text = "⚠ No sync log found yet — has the timer run?"
            failures_log.write_line("No sync log found.")
            return

        try:
            text = SYNC_LOG.read_text()
        except PermissionError:
            statusbar.status_text = "❌ Permission denied reading sync.log"
            failures_log.write_line("Error: Permission denied reading sync.log")
            return
        except OSError as e:
            statusbar.status_text = f"❌ Error reading sync.log: {e}"
            return

        runs = parse_sync_runs(text)
        if not runs:
            statusbar.status_text = "⚠ Sync log exists but no runs parsed yet."
        else:
            last_ts, last_status, last_errs = runs[0]
            icon = "✅" if last_status == "OK" else "❌"
            fail_count = sum(1 for r in runs if r[1] == "FAILED")
            statusbar.status_text = (
                f"{icon} Last run: {last_ts}  |  Status: {last_status}  |  "
                f"Failed runs (recent {len(runs)}): {fail_count}"
            )
            for ts, status, errs in runs[:50]:
                style_status = "[green]OK[/]" if status == "OK" else "[red]FAILED[/]"
                table.add_row(ts, style_status, str(errs))

        # Handle failed.log
        if FAILED_LOG.exists():
            try:
                failures = parse_failures(FAILED_LOG.read_text())
            except PermissionError:
                failures_log.write_line("Error: Permission denied reading failed.log")
                return
            except OSError as e:
                failures_log.write_line(f"Error reading failed.log: {e}")
                return

            if not failures:
                failures_log.write_line("No failures recorded. 🎉")
            else:
                for ts, err in failures[:200]:
                    failures_log.write_line(f"[{ts}] {err}")
        else:
            failures_log.write_line("No failure log yet — nothing has failed so far.")

    def action_refresh_logs(self) -> None:
        self.refresh_data()
        self.notify("Logs refreshed")

    def action_retry_sync(self) -> None:
        if not SYNC_SCRIPT.exists():
            self.notify(f"Sync script not found at {SYNC_SCRIPT}", severity="error")
            return
        if not os.access(SYNC_SCRIPT, os.X_OK):
            self.notify(f"Sync script is not executable: {SYNC_SCRIPT}", severity="error")
            return

        self.notify("Running sync now... this may take a moment")

        # Stream output to the failures log in real-time
        failures_log = self.query_one("#failures_log", Log)
        failures_log.clear()
        failures_log.write_line("=== Starting sync ===")

        try:
            proc = subprocess.Popen(
                [str(SYNC_SCRIPT)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            output_lines = []
            for line in proc.stdout:
                line = line.rstrip()
                output_lines.append(line)
                failures_log.write_line(line)
            proc.wait(timeout=600)

            if proc.returncode == 0:
                self.notify("Sync finished successfully ✅")
            else:
                self.notify(
                    f"Sync exited with code {proc.returncode} ⚠",
                    severity="warning",
                )
        except subprocess.TimeoutExpired:
            proc.kill()
            self.notify("Sync timed out after 10 minutes", severity="error")
        except Exception as e:
            self.notify(f"Error running sync: {e}", severity="error")

        self.refresh_data()


if __name__ == "__main__":
    TeraboxTUI().run()
