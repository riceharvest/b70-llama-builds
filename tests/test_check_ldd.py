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


BUNDLE_SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "bundle-oneapi.sh"


def test_bundle_oneapi_closure_symlinks_and_rpath(tmp_path):
    """scripts/bundle-oneapi.sh copies the ldd closure + dlopen plugins from ONEAPI_ROOT, turns soname symlinks into
    relative symlinks inside $BIN, sets RUNPATH=$ORIGIN with patchelf, and records ONEAPI_BUNDLED.txt."""
    oneapi = tmp_path / "oneapi"
    ver = "2025.3"
    clib = oneapi / "compiler" / ver / "lib"
    mlib = oneapi / "mkl" / ver / "lib"
    clib.mkdir(parents=True)
    mlib.mkdir(parents=True)

    # Real shared library + soname symlink in compiler/lib
    (clib / "libsycl.so.8.1.0").write_text("REAL_SYCL")
    (clib / "libsycl.so.8").symlink_to("libsycl.so.8.1.0")
    # Transitive dependency of libsycl inside compiler/lib
    (clib / "libsvml.so").write_text("REAL_SVML")
    # dlopen plugin (not in ldd output, discovered by glob)
    (clib / "libur_adapter_level_zero.so.0.1.0").write_text("REAL_UR")
    (clib / "libur_adapter_level_zero.so.0").symlink_to("libur_adapter_level_zero.so.0.1.0")
    # MKL CPU dispatch library (discovered by glob)
    (mlib / "libmkl_avx2.so.2").write_text("REAL_MKL_AVX2")

    bindir = tmp_path / "bin"
    bindir.mkdir()
    (bindir / "llama-server").write_text("ELF_BIN")

    stubs = tmp_path / "stubs"
    stubs.mkdir()
    (stubs / "file").write_text('#!/bin/bash\necho "ELF 64-bit LSB shared object"\n')
    # Fake ldd: llama-server depends on libsycl.so.8 (in oneapi) and libze_loader.so.1 (system, outside oneapi);
    # libsycl depends on libsvml.so (transitive in oneapi).
    (stubs / "ldd").write_text(
        f"""#!/bin/bash
case "$1" in
  *llama-server)
    echo "\tlibsycl.so.8 => {clib}/libsycl.so.8 (0x1)"
    echo "\tlibze_loader.so.1 => /usr/lib64/libze_loader.so.1 (0x2)"
    ;;
  *libsycl.so*)
    echo "\tlibsvml.so => {clib}/libsvml.so (0x3)"
    ;;
esac
"""
    )
    rpath_log = tmp_path / "patchelf.log"
    (stubs / "patchelf").write_text(f'#!/bin/bash\necho "$*" >> "{rpath_log}"\n')
    for s in ("file", "ldd", "patchelf"):
        (stubs / s).chmod(0o755)

    env = {
        **os.environ,
        "PATH": f"{stubs}:{os.environ['PATH']}",
        "ONEAPI_ROOT": str(oneapi),
        "ONEAPI_VERSION": ver,
    }
    r = subprocess.run(["bash", str(BUNDLE_SCRIPT), str(bindir)], env=env, capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stderr

    # Real files copied once; sonames are relative symlinks inside bindir
    assert (bindir / "libsycl.so.8.1.0").is_file() and not (bindir / "libsycl.so.8.1.0").is_symlink()
    assert (bindir / "libsycl.so.8").is_symlink()
    assert os.readlink(bindir / "libsycl.so.8") == "libsycl.so.8.1.0"
    assert (bindir / "libsvml.so").is_file()  # transitive dep pulled in
    assert (bindir / "libur_adapter_level_zero.so.0").is_symlink()
    assert (bindir / "libmkl_avx2.so.2").is_file()  # dlopen glob pulled in
    assert not (bindir / "libze_loader.so.1").exists()  # system lib outside ONEAPI_ROOT is NOT bundled

    bundled = (bindir / "ONEAPI_BUNDLED.txt").read_text().splitlines()
    assert bundled == sorted(["libmkl_avx2.so.2", "libsycl.so.8.1.0", "libsvml.so", "libur_adapter_level_zero.so.0.1.0"])

    # patchelf --set-rpath $ORIGIN called on every copied real library
    patched = rpath_log.read_text().splitlines()
    assert len(patched) == 4 and all("--set-rpath $ORIGIN " in line for line in patched)
