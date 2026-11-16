#!/usr/bin/env python3
"""Build Eir for Windows and package Microsoft Store MSIX on the Windows builder machine."""
import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SSH_PORT = "14320"
SSH_HOST = "127.0.0.1"
SSH_USER = "builder"
SSH_KEY = os.path.expanduser("~/.ssh/id_ed25519")
REMOTE_DIR = r"C:\valhalla-build\eir-build"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def run_ssh(cmd: str, check: bool = True) -> subprocess.CompletedProcess:
    ssh_cmd = [
        "ssh", "-p", SSH_PORT,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-i", SSH_KEY,
        f"{SSH_USER}@{SSH_HOST}",
        cmd,
    ]
    print(f"==> SSH Exec: {cmd[:100]}...", flush=True)
    res = subprocess.run(ssh_cmd, capture_output=True, text=True)
    if check and res.returncode != 0:
        print(f"STDERR:\n{res.stderr}", flush=True)
        print(f"STDOUT:\n{res.stdout}", flush=True)
        raise RuntimeError(f"SSH command failed with returncode {res.returncode}")
    return res


def sync_workspace():
    print(f"[*] Cleaning and creating remote build directory: {REMOTE_DIR}...", flush=True)
    run_ssh(f'powershell -NoProfile -Command "if (Test-Path {REMOTE_DIR}) {{ Remove-Item -Path {REMOTE_DIR} -Recurse -Force }}; New-Item -ItemType Directory -Path {REMOTE_DIR} -Force | Out-Null"')

    print("[*] Streaming workspace to remote Windows machine via tar...", flush=True)
    tar_cmd = [
        "tar",
        "--exclude=build",
        "--exclude=.dart_tool",
        "--exclude=.git",
        "--exclude=eir-v*.apk",
        "--exclude=*.zip",
        "--exclude=*.msix",
        "-czf", "-", ".",
    ]
    ssh_receive_cmd = [
        "ssh", "-p", SSH_PORT,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-i", SSH_KEY,
        f"{SSH_USER}@{SSH_HOST}",
        f'tar -xzf - -C {REMOTE_DIR}',
    ]
    p_tar = subprocess.Popen(tar_cmd, cwd=ROOT, stdout=subprocess.PIPE)
    p_ssh = subprocess.Popen(ssh_receive_cmd, stdin=p_tar.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p_tar.stdout.close()
    out, err = p_ssh.communicate()
    if p_ssh.returncode != 0:
        raise RuntimeError(f"Workspace sync failed: {err.decode('utf-8', errors='replace')}")
    print("[*] Workspace synced successfully.", flush=True)


def build_and_package():
    remote_script = rf"{REMOTE_DIR}\tool\run_windows_build.ps1"
    print(f"[*] Executing Windows build script: {remote_script}...", flush=True)
    cmd = [
        "ssh", "-p", SSH_PORT,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-i", SSH_KEY,
        f"{SSH_USER}@{SSH_HOST}",
        f'powershell -NoProfile -ExecutionPolicy Bypass -File "{remote_script}"',
    ]

    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in iter(p.stdout.readline, ""):
        print(line, end="", flush=True)
    p.stdout.close()
    rc = p.wait()

    if rc != 0:
        raise RuntimeError(f"Remote Windows build failed with exit code {rc}")
    print("[*] Remote Windows build and packaging completed successfully.", flush=True)


def fetch_artifacts():
    print("[*] Fetching Windows MSIX and ZIP artifacts back to workspace...", flush=True)
    local_artifacts_dir = ROOT / "build/windows-artifacts"
    local_artifacts_dir.mkdir(parents=True, exist_ok=True)

    # Use scp -O (legacy scp protocol) to prevent 200KB truncation bug on this SSH server
    remote_src = f"{SSH_USER}@{SSH_HOST}:{REMOTE_DIR}/build/windows-artifacts/*"
    scp_cmd = [
        "scp", "-O", "-P", SSH_PORT,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-i", SSH_KEY,
        remote_src,
        str(local_artifacts_dir),
    ]
    print(f"==> Running scp -O to {local_artifacts_dir}...", flush=True)
    res = subprocess.run(scp_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Artifact fetch failed: {res.stderr}")

    # Copy msix to root for easy user access
    for item in local_artifacts_dir.glob("*.msix"):
        dest = ROOT / item.name
        import shutil
        shutil.copy2(item, dest)
        size = dest.stat().st_size
        sha = sha256_file(dest)
        print(f"\n[SUCCESS] Store MSIX Artifact: {dest}")
        print(f"  Size: {size:,} bytes ({size / (1024*1024):.2f} MB)")
        print(f"  SHA-256: {sha}")

    for item in local_artifacts_dir.glob("*.zip"):
        dest = ROOT / item.name
        import shutil
        shutil.copy2(item, dest)
        size = dest.stat().st_size
        sha = sha256_file(dest)
        print(f"\n[SUCCESS] Portable ZIP Artifact: {dest}")
        print(f"  Size: {size:,} bytes ({size / (1024*1024):.2f} MB)")
        print(f"  SHA-256: {sha}")


def main():
    start = time.time()
    sync_workspace()
    build_and_package()
    fetch_artifacts()
    elapsed = time.time() - start
    print(f"\n[DONE] Windows build & packaging completed in {elapsed:.1f}s.")


if __name__ == "__main__":
    main()
