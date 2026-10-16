#!/usr/bin/env python3
# Verify production sandbox against executable probes and native CLI startup.
# Run: python3 scripts/verify-sandbox.py [--native-cli] after scripts/verify-assistant.sh.
# Requires macOS clang; --native-cli also requires installed Claude/Codex. Synthetic files only.
import argparse, json, os, pathlib, subprocess, tempfile, socket
parser=argparse.ArgumentParser()
parser.add_argument('--native-cli',action='store_true',help='Also require and verify locally installed native Claude/Codex startup')
options=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='ts-sb-',dir='/tmp') as temp:
    base=pathlib.Path(temp).resolve();work=base/'work';work.mkdir(mode=0o700)
    secret=base/'outside.txt';secret.write_text('synthetic canary')
    unix=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);socket_path=str(base/'probe.sock');unix.bind(socket_path);unix.listen(1)
    probe=base/'probe'
    subprocess.run(['xcrun','clang','-Wall','-Wextra','-Werror',str(root/'tests/sandbox-probe.c'),'-o',str(probe)],check=True)
    def args(executable,extra=()):
        return json.loads(subprocess.check_output([str(root/'build/test-assistant'),'--sandbox-args',str(executable),str(work)]+list(extra),text=True))
    env={'HOME':str(work),'TMPDIR':str(work),'PATH':'/usr/bin:/bin'}
    for extra,mode in [((), 'custom'),(('--login',),'login'),(('--codex',),'codex-custom'),(('--codex','--login'),'codex-login')]:
        target=work/('allowed-'+mode+'.txt')
        subprocess.run(['/usr/bin/sandbox-exec']+args(probe,extra)+[str(probe),str(secret),str(target),mode,socket_path],env=env,cwd=work,check=True,timeout=15)
    assert secret.read_text()=='synthetic canary'
    executables=[pathlib.Path.home()/'.local/bin/claude',pathlib.Path.home()/'.codex/packages/standalone/current/bin/codex'] if options.native_cli else []
    for executable in executables:
        if not executable.exists():raise SystemExit(f'Missing native CLI: {executable.name}')
        actual=executable.resolve()
        result=subprocess.run(['/usr/bin/sandbox-exec']+args(actual)+[str(actual),'--version'],env=env,cwd=work,capture_output=True,text=True,timeout=20)
        if result.returncode:raise SystemExit(f'{executable.name} sandbox startup failed ({result.returncode}): {result.stderr[:500]}')
        print('PASS native CLI startup:',result.stdout.strip())
