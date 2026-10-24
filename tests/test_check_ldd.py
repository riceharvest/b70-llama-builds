"""scripts/check-ldd.sh on CPU: fake `ldd` and `file` binaries stand in for real ELF files, so the test checks the
script's own logic (which libraries count as unresolved, the allow-list regex, the exit code)."""
import os
import pathlib
import subprocess

import pytest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "check-ldd.sh"

# `file -b X` says ELF unless the name ends in .txt; `ldd X` reads the missing libraries from X's own content.
FILE_STUB = '#!/bin/bash\ncase "$2" in *.txt) echo "ASCII text";; *) echo "ELF 64-bit LSB shared object";; esac\n'
LDD_STUB = '#!/bin/bash\nwhile read -r l; do echo "	$l => not found"; done < "$1"\necho "	libc.so.6 => /lib64/libc.so.6 (0x1)"\n'


@pytest.fixture
def run(tmp_path):
    bindir, binaries = tmp_path / "stubs", tmp_path / "bin"
    bindir.mkdir()
    binaries.mkdir()
    for name, body in (("file", FILE_STUB), ("ldd", LDD_STUB)):
        (bindir / name).write_text(body)
        (bindir / name).chmod(0o755)

    def _run(files, allow=None):
        for name, missing in files.items():
            (binaries / name).write_text("".join(m + "\n" for m in missing))
        args = ["bash", str(SCRIPT), str(binaries)] + ([allow] if allow is not None else [])
        env = {**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "LD_LIBRARY_PATH": "/nonexistent"}
        return subprocess.run(args, env=env, capture_output=True, text=True, check=False)

    return _run


def test_all_resolved_passes(run):
    r = run({"llama-server": [], "llama-cli": []})
    assert r.returncode == 0 and "all libraries resolve" in r.stdout


def test_missing_library_fails_and_names_file(run):
    r = run({"llama-server": ["libsycl.so.8", "libur_loader.so.0"], "llama-cli": []})
    assert r.returncode == 1
    assert "UNRESOLVED in llama-server: libsycl.so.8 libur_loader.so.0" in r.stdout
    assert "llama-cli" not in r.stdout


def test_allow_list_ignores_system_libraries(run):
    r = run({"llama-server": ["libze_loader.so.1"]}, allow=r"^libze_loader\.so")
    assert r.returncode == 0 and "allowed missing: ^libze_loader" in r.stdout
    r = run({"llama-server": ["libze_loader.so.1", "libsycl.so.8"]}, allow=r"^libze_loader\.so")
    assert r.returncode == 1 and "libsycl.so.8" in r.stdout and "libze_loader" not in r.stdout.split("UNRESOLVED")[1]


def test_non_elf_files_are_skipped(run):
    r = run({"README.txt": ["libfoo.so"], "llama-server": []})
    assert r.returncode == 0


def test_duplicates_listed_once(run):
    r = run({"llama-server": ["libsycl.so.8", "libsycl.so.8"]})
    assert r.stdout.count("libsycl.so.8") == 1
