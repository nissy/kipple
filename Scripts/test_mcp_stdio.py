"""Verify client handshakes, the MCP schema and rejected inputs without clipboard writes."""

import json
import os
from pathlib import Path
import select
import subprocess
import sys
import uuid


def verify_session(helper, capabilities):
    environment = {key: value for key, value in os.environ.items() if not key.startswith("KIPPLE_")}
    process = subprocess.Popen(
        [str(helper)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=environment,
    )

    def request(method, params, identifier):
        process.stdin.write(json.dumps({
            "jsonrpc": "2.0", "id": identifier, "method": method, "params": params,
        }) + "\n")
        process.stdin.flush()
        if not select.select([process.stdout], [], [], 8)[0]:
            raise AssertionError("MCP response timed out: " + method)
        line = process.stdout.readline()
        assert line, f"MCP server closed stdout during {method} (exit: {process.poll()})"
        response = json.loads(line)
        assert response["id"] == identifier
        assert "error" not in response, f"{method} failed: {response.get('error')}"
        return response["result"]

    try:
        initialized = request("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": capabilities,
            "clientInfo": {"name": "Kipple test", "version": "1.0"},
        }, 1)
        assert initialized["serverInfo"]["name"] == "Kipple"
        process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        process.stdin.flush()
        tools = request("tools/list", {}, 2)["tools"]
        assert [tool["name"] for tool in tools] == ["kipple_add_items"]
        assert tools[0]["annotations"]["readOnlyHint"] is False
        item_schema = tools[0]["inputSchema"]["properties"]["items"]["items"]
        assert item_schema["required"] == ["content"]
        assert item_schema["properties"]["content"]["maxLength"] == 80000
        assert set(item_schema["properties"]) == {"content", "title"}
        invalid_requests = [
            ({"items": []}, "INVALID_INPUT"),
            ({"items": [{"content": "Test", "sensitive": False}]}, "INVALID_INPUT"),
            ({"items": [{"content": "Test", "expiresAt": None}]}, "INVALID_INPUT"),
            ({"items": [{"filePath": "/unavailable.txt"}]}, "INVALID_INPUT"),
            ({"items": [{"content": "Test"}], "token": "obsolete"}, "INVALID_INPUT"),
            ({"items": [{"content": "あ" * 80001}]}, "PAYLOAD_TOO_LARGE"),
            ({"items": [{"content": "😀" * 80001}]}, "PAYLOAD_TOO_LARGE"),
        ]
        for identifier, (arguments, expected_code) in enumerate(invalid_requests, start=3):
            arguments["requestId"] = str(uuid.uuid4())
            result = request("tools/call", {
                "name": "kipple_add_items", "arguments": arguments,
            }, identifier)
            assert result["isError"] is True
            assert result["structuredContent"]["code"] == expected_code
    finally:
        process.terminate()
        process.wait(timeout=5)
        assert not process.stderr.read(), "Unexpected MCP stderr output"


def main():
    helper = Path(sys.argv[1]).resolve(strict=True)
    for capabilities in [
        {},
        # Codex 0.154.0+: this valid object failed with Swift SDK 0.12.1.
        {"experimental": {"codex/auth-change": {}}},
        {
            "experimental": {"openai/visibility": {"enabled": True}},
            "extensions": {
                "io.modelcontextprotocol/ui": {"mimeTypes": ["text/html;profile=mcp-app"]},
            },
            "roots": {"listChanged": True},
            "sampling": {},
            "elicitation": {"form": {}, "url": {}},
        },
    ]:
        verify_session(helper, capabilities)
    print("MCP stdio: basic/Codex/nested-capability handshakes, tokenless schema, "
          "removed fields and 80,000-character limits passed.")


if __name__ == "__main__":
    main()
