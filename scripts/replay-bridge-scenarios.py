#!/usr/bin/env python3
"""
Replay bridge events into a running Open Island dev app.

This is a manual UI verification helper.  It sends realistic bridge commands
over the same Unix socket used by hook clients.  Permission/question events keep
their socket open by default, matching real blocking hook/plugin processes while
the UI waits for user input.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import time
import uuid
from pathlib import Path
from typing import Any


SCENARIOS = ("approval", "question", "question-hook", "completion", "all")
DEFAULT_FIRE_AND_FORGET_PAUSE = 0.15
DEFAULT_HOLD_TIMEOUT = 0.0


def default_socket_path() -> str:
    path = os.environ.get("NOTCHTUNE_SOCKET_PATH") or os.environ.get("VIBE_ISLAND_SOCKET_PATH")
    if path:
        return path
    return str(Path.home() / "Library/Application Support/NotchTune/bridge.sock")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def base_payload(session_id: str, cwd: str, terminal_title: str) -> dict[str, Any]:
    return {
        "cwd": cwd,
        "session_id": session_id,
        "terminal_app": "Ghostty",
        "terminal_session_id": f"replay-{session_id}",
        "terminal_title": terminal_title,
    }


def codex_payload(
    event: str,
    session_id: str,
    *,
    cwd: str,
    prompt: str | None = None,
    tool_name: str | None = None,
    tool_input: dict[str, Any] | None = None,
    last_assistant_message: str | None = None,
) -> dict[str, Any]:
    payload = {
        **base_payload(session_id, cwd, "codex replay ~/Personal/open-island"),
        "hook_event_name": event,
        "model": "gpt-5.3-codex-replay",
        "permission_mode": "default",
        "transcript_path": f"/tmp/open-island-{session_id}.jsonl",
    }
    if prompt is not None:
        payload["prompt"] = prompt
    if tool_name is not None:
        payload["tool_name"] = tool_name
        payload["tool_use_id"] = f"tool-{session_id}"
    if tool_input is not None:
        payload["tool_input"] = tool_input
    if last_assistant_message is not None:
        payload["last_assistant_message"] = last_assistant_message
    return payload


def opencode_payload(
    event: str,
    session_id: str,
    *,
    cwd: str,
    prompt: str | None = None,
    tool_name: str | None = None,
    tool_input: str | None = None,
    question_text: str | None = None,
    questions: list[dict[str, Any]] | None = None,
    last_assistant_message: str | None = None,
) -> dict[str, Any]:
    payload = {
        **base_payload(session_id, cwd, "opencode replay ~/Personal/open-island"),
        "hook_event_name": event,
        "model": "opencode-replay",
    }
    if prompt is not None:
        payload["prompt"] = prompt
    if tool_name is not None:
        payload["tool_name"] = tool_name
    if tool_input is not None:
        payload["tool_input"] = tool_input
    if question_text is not None:
        payload["question_id"] = f"question-{session_id}"
        payload["question_text"] = question_text
    if questions is not None:
        payload["questions"] = questions
    if last_assistant_message is not None:
        payload["last_assistant_message"] = last_assistant_message
    return payload


def command_envelope(command: dict[str, Any]) -> dict[str, Any]:
    return {"type": "command", "command": command}


def process_codex_hook(payload: dict[str, Any]) -> dict[str, Any]:
    return command_envelope({"type": "processCodexHook", "codexHook": payload})


def process_opencode_hook(payload: dict[str, Any]) -> dict[str, Any]:
    return command_envelope({"type": "processOpenCodeHook", "openCodeHook": payload})


def request_question(session_id: str, title: str, questions: list[dict[str, Any]]) -> dict[str, Any]:
    resolved_questions = []
    flat_options = []
    for question in questions:
        resolved_options = []
        for option in question.get("options", []):
            label = option["label"]
            flat_options.append(label)
            resolved_options.append(
                {
                    "id": str(uuid.uuid4()),
                    "label": label,
                    "description": option.get("description", ""),
                    "allowsFreeform": option.get("allows_freeform", False),
                }
            )

        resolved_questions.append(
            {
                "question": question["question"],
                "header": question.get("header", "Question"),
                "options": resolved_options,
                "multiSelect": question.get("multi_select", False),
            }
        )

    return command_envelope(
        {
            "type": "requestQuestion",
            "sessionID": session_id,
            "prompt": {
                "id": str(uuid.uuid4()),
                "title": title,
                "options": flat_options,
                "questions": resolved_questions,
            },
        }
    )


def replay_question_prompt() -> tuple[str, list[dict[str, Any]]]:
    title = "Which notification treatment should this session use?"
    questions = [
        {
            "question": title,
            "header": "Notification",
            "options": [
                {
                    "label": "Inline choices",
                    "description": "Answer directly in the island",
                },
                {
                    "label": "Jump back",
                    "description": "Return to the terminal before answering",
                },
                {
                    "label": "Other",
                    "description": "Type a custom reply",
                    "allows_freeform": True,
                },
            ],
        }
    ]
    return title, questions


def scenario_commands(scenario: str, cwd: str) -> list[tuple[str, dict[str, Any], bool, bool]]:
    if scenario == "approval":
        session_id = "open-island-replay-approval"
        return [
            (
                "codex session start",
                process_codex_hook(codex_payload("SessionStart", session_id, cwd=cwd)),
                True,
                False,
            ),
            (
                "codex prompt",
                process_codex_hook(
                    codex_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd=cwd,
                        prompt="Replay the approval notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "codex approval request",
                process_codex_hook(
                    codex_payload(
                        "PreToolUse",
                        session_id,
                        cwd=cwd,
                        tool_name="exec_command",
                        tool_input={"command": "swift test --filter AppModelSessionListTests"},
                    )
                ),
                False,
                True,
            ),
        ]

    if scenario == "question":
        session_id = "open-island-replay-question"
        question_title, questions = replay_question_prompt()
        return [
            (
                "opencode session start",
                process_opencode_hook(opencode_payload("SessionStart", session_id, cwd=cwd)),
                True,
                False,
            ),
            (
                "opencode prompt",
                process_opencode_hook(
                    opencode_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd=cwd,
                        prompt="Replay the question notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "bridge question",
                request_question(session_id, question_title, questions),
                True,
                False,
            ),
        ]

    if scenario == "question-hook":
        session_id = "open-island-replay-question-hook"
        question_title, questions = replay_question_prompt()
        return [
            (
                "opencode session start",
                process_opencode_hook(opencode_payload("SessionStart", session_id, cwd=cwd)),
                True,
                False,
            ),
            (
                "opencode prompt",
                process_opencode_hook(
                    opencode_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd=cwd,
                        prompt="Replay the question notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "opencode question hook",
                process_opencode_hook(
                    opencode_payload(
                        "QuestionAsked",
                        session_id,
                        cwd=cwd,
                        question_text=question_title,
                        questions=questions,
                    )
                ),
                False,
                True,
            ),
        ]

    if scenario == "completion":
        session_id = "open-island-replay-completion"
        return [
            (
                "codex session start",
                process_codex_hook(codex_payload("SessionStart", session_id, cwd=cwd)),
                True,
                False,
            ),
            (
                "codex prompt",
                process_codex_hook(
                    codex_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd=cwd,
                        prompt="Replay the completion notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "codex stop",
                process_codex_hook(
                    codex_payload(
                        "Stop",
                        session_id,
                        cwd=cwd,
                        last_assistant_message=(
                            "Bridge replay finished. Use this card to verify completed-session "
                            "notification layout and reply affordances."
                        ),
                    )
                ),
                True,
                False,
            ),
        ]

    raise ValueError(f"unsupported scenario: {scenario}")


def recv_response(sock: socket.socket, timeout: float | None) -> dict[str, Any] | None:
    sock.settimeout(timeout)
    buffer = b""
    try:
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                return None
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if not line:
                    continue
                message = json.loads(line)
                if message.get("type") == "response":
                    return message.get("response")
    except (TimeoutError, socket.timeout):
        return None


def connect_bridge(socket_path: str) -> socket.socket:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(socket_path)
    except FileNotFoundError:
        sock.close()
        raise RuntimeError(
            f"Bridge socket not found at {socket_path}. Start the dev app with `zsh scripts/launch-dev-app.sh`."
        )
    except ConnectionRefusedError:
        sock.close()
        raise RuntimeError(
            f"Bridge socket refused connection at {socket_path}. Restart the dev app and try again."
        )
    return sock


def encode_envelope(envelope: dict[str, Any]) -> str:
    return json.dumps(envelope, separators=(",", ":"))


def send_envelope(
    socket_path: str,
    envelope: dict[str, Any],
    *,
    wait_response: bool,
    timeout: float,
    dry_run: bool,
) -> dict[str, Any] | None:
    line = encode_envelope(envelope)
    if dry_run:
        print(line)
        return {"type": "dryRun"}

    with connect_bridge(socket_path) as sock:
        sock.sendall(line.encode("utf-8") + b"\n")
        if wait_response:
            return recv_response(sock, timeout)

        time.sleep(DEFAULT_FIRE_AND_FORGET_PAUSE)
        return None


def hold_interaction(
    socket_path: str,
    envelope: dict[str, Any],
    *,
    timeout: float | None,
    dry_run: bool,
    label: str,
) -> dict[str, Any] | None:
    line = encode_envelope(envelope)
    if dry_run:
        print(line)
        return {"type": "dryRun"}

    with connect_bridge(socket_path) as sock:
        sock.sendall(line.encode("utf-8") + b"\n")
        print(f"  sent {label}; keeping hook connected until UI resolution")
        print("  answer the card in Open Island, or press Ctrl-C to cancel")
        return recv_response(sock, timeout)


def replay_one(
    scenario: str,
    *,
    socket_path: str,
    cwd: str,
    timeout: float,
    hold_timeout: float | None,
    hold_interactions: bool,
    dry_run: bool,
) -> None:
    print(f"Replaying {scenario} bridge scenario")
    for label, envelope, wait_response, can_hold in scenario_commands(scenario, cwd):
        if can_hold and hold_interactions:
            response = hold_interaction(
                socket_path,
                envelope,
                timeout=hold_timeout,
                dry_run=dry_run,
                label=label,
            )
            if dry_run:
                print(f"  sent {label}")
            elif response is None:
                print(f"  {label} ended without a bridge response")
            else:
                print(f"  resolved {label}")
            continue
        else:
            response = send_envelope(
                socket_path,
                envelope,
                wait_response=wait_response,
                timeout=timeout,
                dry_run=dry_run,
            )
        if wait_response and response is None and not dry_run:
            raise RuntimeError(f"{label} did not return a bridge response")
        print(f"  sent {label}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Replay Open Island bridge scenarios into the running dev app."
    )
    parser.add_argument(
        "scenario",
        choices=SCENARIOS,
        help="Scenario to replay. Use individual scenarios for manual visual inspection.",
    )
    parser.add_argument(
        "--socket",
        default=default_socket_path(),
        help="Bridge socket path. Defaults to NOTCHTUNE_SOCKET_PATH or the stable NotchTune app-support socket.",
    )
    parser.add_argument(
        "--cwd",
        default=str(repo_root()),
        help="Working directory to place in replay payloads.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5,
        help="Response timeout for non-blocking bridge commands.",
    )
    parser.add_argument(
        "--hold-timeout",
        type=float,
        default=DEFAULT_HOLD_TIMEOUT,
        help="Seconds to keep approval/question replay hooks connected while waiting for UI resolution. 0 waits indefinitely.",
    )
    parser.add_argument(
        "--no-hold",
        action="store_true",
        help="Do not keep approval/question hooks connected. Mostly useful for inspecting raw bridge cleanup behavior.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=1.4,
        help="Delay between scenarios when using `all`.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print JSON envelopes without connecting to the bridge.",
    )
    args = parser.parse_args()

    scenarios = ("approval", "question", "completion") if args.scenario == "all" else (args.scenario,)
    hold_interactions = not args.no_hold and args.scenario != "all"
    hold_timeout = None if args.hold_timeout <= 0 else args.hold_timeout

    if args.scenario == "all" and not args.no_hold and not args.dry_run:
        print("`all` replays without holding approval/question sockets; use an individual scenario for UI inspection.")

    try:
        for index, scenario in enumerate(scenarios):
            if index:
                time.sleep(args.delay)
            replay_one(
                scenario,
                socket_path=args.socket,
                cwd=args.cwd,
                timeout=args.timeout,
                hold_timeout=hold_timeout,
                hold_interactions=hold_interactions,
                dry_run=args.dry_run,
            )
    except KeyboardInterrupt:
        print("\nReplay cancelled.")
        return 130
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.dry_run:
        print("Dry run complete.")
    else:
        print("Replay complete. Inspect the Open Island overlay.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
