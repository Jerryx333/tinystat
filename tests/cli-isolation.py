#!/usr/bin/env python3
# Verify installed CLI isolation using synthetic credentials and a local fake API.
# Run: python3 tests/cli-isolation.py; no external network calls or user data.
# Requires Python 3 and installed codex/claude executables.
import http.server
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
source = (ROOT / 'Sources/AgentBackend.swift').read_text()
features = re.findall(r'"([a-z_]+)"', re.search(r'disabledCodexFeatures=\[([^\]]+)\]', source)[1])
requests = []

class Server(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        raw = self.rfile.read(int(self.headers['Content-Length']))
        requests.append((json.loads(raw), dict(self.headers)))
        self.send_response(400)
        self.end_headers()
        self.wfile.write(b'{"error":{"message":"synthetic probe complete","type":"invalid_request_error"}}')
    def log_message(self, *args):
        pass

server = http.server.HTTPServer(('127.0.0.1', 0), Server)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    for kind in ('codex', 'claude'):
        executable = shutil.which(kind)
        assert executable, f'{kind} not installed'
        with tempfile.TemporaryDirectory(prefix='tinystat-isolation-') as tmp:
            home = pathlib.Path(tmp)
            marker = home / 'HOOK_RAN'
            claude = home / '.claude'
            claude.mkdir()
            (claude / 'CLAUDE.md').write_text('TINYSTAT_UNTRUSTED_INSTRUCTIONS_MARKER')
            hook = {'type': 'command', 'command': f'touch {marker}'}
            (claude / 'settings.json').write_text(json.dumps({'hooks': {'SessionStart': [{'hooks': [hook]}], 'UserPromptSubmit': [{'hooks': [hook]}]}}))
            codex = home / '.codex'
            codex.mkdir()
            (codex / 'AGENTS.md').write_text('TINYSTAT_UNTRUSTED_INSTRUCTIONS_MARKER')
            (codex / 'config.toml').write_text(f'notify = ["/usr/bin/touch", "{marker}"]\n[mcp_servers.trap]\ncommand = "/usr/bin/touch"\nargs = ["{marker}"]\n')
            env = {'HOME': tmp, 'CODEX_HOME': str(codex), 'CLAUDE_CONFIG_DIR': str(claude), 'PATH': os.path.dirname(executable) + ':/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin', 'LANG': 'en_US.UTF-8'}
            endpoint = f'http://127.0.0.1:{server.server_port}/v1'
            if kind == 'codex':
                isolated = home / 'isolated-codex'
                isolated.mkdir()
                env['CODEX_HOME'] = str(isolated)
                env['TINYSTAT_PROVIDER_KEY'] = 'synthetic-not-a-credential'
                args = ['exec', '--ignore-user-config', '--ignore-rules', '--ephemeral', '--skip-git-repo-check', '--json', '-s', 'read-only', '-C', tmp, '-m', 'test-model']
                config = {'model_provider': 'tinystat', 'model_providers.tinystat.name': 'TinyStat', 'model_providers.tinystat.base_url': endpoint, 'model_providers.tinystat.env_key': 'TINYSTAT_PROVIDER_KEY', 'model_providers.tinystat.wire_api': 'responses', 'web_search': 'disabled'}
                for key, value in config.items():
                    args += ['-c', key + '=' + json.dumps(value)]
                args += ['-c', 'project_doc_max_bytes=0', '-c', 'model_providers.tinystat.request_max_retries=0', '-c', 'model_providers.tinystat.stream_max_retries=0']
                for feature in features:
                    args += ['--disable', feature]
                args += ['--enable', 'skip_host_skill_discovery', '-']
            else:
                env.update(ANTHROPIC_BASE_URL=endpoint.removesuffix('/v1'), ANTHROPIC_API_KEY='synthetic-not-a-credential', CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1', DISABLE_AUTOUPDATER='1')
                args = ['-p', '--safe-mode', '--tools', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--disable-slash-commands', '--no-session-persistence', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'dontAsk', '--system-prompt', 'Reply OK only. No tools.', '--model', 'test-model']
            if kind == 'claude':
                control = [arg for arg in args if arg != '--safe-mode']
                subprocess.run([executable] + control, input='Synthetic isolation control.', text=True, env=env, cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45, check=False)
                assert marker.exists(), 'Claude control did not run fixture hook; test inconclusive'
                marker.unlink()
                print('PASS claude control: fixture hook executes without safe-mode')
            requests.clear()
            subprocess.run([executable] + args, input='Synthetic isolation test.', text=True, env=env, cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45, check=False)
            assert requests, f'{kind}: no request captured'
            assert not marker.exists(), f'{kind}: hooks/MCP/notify ran'
            for body, headers in requests:
                serialized = json.dumps(body)
                assert 'TINYSTAT_UNTRUSTED_INSTRUCTIONS_MARKER' not in serialized, f'{kind}: loaded global instructions'
                tools = body.get('tools', [])
                assert all(t.get('name') == 'request_user_input' for t in tools) if kind == 'codex' else not tools, f'{kind}: unexpected tools'
                auth = {k.lower(): v for k, v in headers.items() if k.lower() in ('authorization', 'x-api-key')}
                assert auth and all('synthetic-not-a-credential' in v for v in auth.values()), f'{kind}: unexpected auth source'
            print(f'PASS {kind}: local synthetic requests, no shell/MCP/file tools, no hooks, no global instructions, synthetic authentication only')
finally:
    server.shutdown()
