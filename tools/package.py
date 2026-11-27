"""Build Suitcase's portable package with the Hailstone add-on packager."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory


def stage_file(source, destination):
    source = Path(source)
    destination = Path(destination)
    if source.name == "LICENSE" or source.suffix in {".ini", ".lua", ".md", ".txt"}:
        destination.write_bytes(source.read_bytes().replace(b"\r\n", b"\n"))
        return destination
    return shutil.copyfile(source, destination)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=root.parent / "hailstone-client")
    parser.add_argument("--out", type=Path, default=root / "dist")
    parser.add_argument("--version", default="0.1.4")
    args = parser.parse_args()
    packager = args.client / "tools" / "make_addon.py"
    if not packager.is_file():
        parser.error("Supply a Hailstone checkout with --client.")

    with TemporaryDirectory(prefix="hailstone-suitcase-") as temp:
        staging = Path(temp)
        for name in ("LICENSE", "README.md", "init.lua"):
            stage_file(root / name, staging / name)
        shutil.copytree(root / "ui", staging / "ui", copy_function=stage_file)
        subprocess.run(
            [
                sys.executable, str(packager), "--kind", "script", "--name", "suitcase",
                "--version", args.version, "--min-client", "0.7.3-beta", "--autoload",
                "--caps", "read,ui,actions,commands", "--author", "Fryguy",
                "--description", "Save and swap sets of worn gear from your bags.",
                "--dir", str(staging), "--out", str(args.out),
            ],
            check=True,
        )


if __name__ == "__main__":
    main()
