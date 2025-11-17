#! /usr/bin/env python3.11

# NOTE: make sure permission for snapshotting is allowed on pools
#
# This version is written for Borg 1.x (e.g. 1.4.x packaging).
# It assumes:
#   - "borg info" is used to test repo existence
#   - "borg init --encryption=repokey-blake2" to create repos
#   - archive names are explicit, not using Borg 2.x "{now}" syntax

import argparse
import logging
import os
import secrets
import shlex
import subprocess
import tomllib
from datetime import datetime, timedelta
from logging.handlers import RotatingFileHandler
from pathlib import Path

LOG_FMT = "[%(name)s][%(asctime)s][%(levelname)s]: %(message)s"
logging.basicConfig(format=LOG_FMT)
logger = logging.getLogger("backups")
logger.setLevel(logging.DEBUG)

AUTO_PREFIX = "auto"
BACKUP_PROPERTY = "backup:done"
BORG_SUCCESS = 0
BORG_WARN = 1
BORG_ERROR = 2
BORG_PASSPHRASE = None
BORG_KEYFILE_EXPORT_DIR = None


def failexit(reason: str):
    logger.error(reason)
    raise RuntimeError("failed")


def execute(cmd: str):
    try:
        return subprocess.check_output(
            shlex.split(cmd), text=True, stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        logger.exception(f"Failed call: {cmd} = {e.returncode}\n{e.output}")
        raise


def borg_cmd(cmd: str, env: dict | None = None, check: bool = True, **kwargs):
    p = subprocess.run(
        shlex.split(cmd), env=env, text=True, capture_output=True, **kwargs
    )

    if check:
        output = []
        if p.stdout:
            output.append(p.stdout)
        if p.stderr:
            output.append(p.stderr)

        output = "\n".join(output)

        match p.returncode:
            case 2:
                failexit(f"Borg command failed fatally\n{output}")
            case 1:
                logger.warning(f"Borg command warning\n{output}")

    return p


def list_snapshots(fs: str):
    return execute(f"zfs list -H -t snapshot -o name {fs}").strip().split("\n")


def is_snapshot_backed_up(snapshot: str):
    try:
        return bool(int(execute(f"zfs get {BACKUP_PROPERTY} -o value -H {snapshot}")))
    except ValueError:
        return False


def mark_snapshot_backed_up(snapshot: str):
    execute(f"zfs set {BACKUP_PROPERTY}=1 {snapshot}")


def zfs_destroy(item: str):
    assert "@" in item, f"Oh boy, destroy {item}?"
    execute(f"zfs destroy {item}")


def get_fs_mountpoint(fs: str):
    return execute(f"zfs list -o mountpoint -H {fs}").strip()


def parse_archive_tag(tag: str):
    dash = tag.index("-")
    # prefix (type), time
    return tag[:dash], datetime.fromisoformat(tag[dash + 1 :])


def find_last_snapshot(fs: str, prefix: str):
    snaps = filter(
        lambda t: t[0].startswith(prefix), map(parse_archive_tag, list_snapshots(fs))
    )
    snaps = sorted(snaps, key=lambda t: t[1], reverse=True)
    return snaps[0] if len(snaps) else None


def snapshot(fs: str, name: str):
    full_name = f"{fs}@{name}"
    execute(f"zfs snapshot {full_name}")
    return name


def make_borg_env(repo: str):
    return {**os.environ, "BORG_PASSPHRASE": BORG_PASSPHRASE, "BORG_REPO": repo}


def do_backup(snapshot: str, conf: dict):
    # snapshot is "pool/fs@tag"
    fs, snap_name = snapshot.split("@")
    prefix, dt = parse_archive_tag(snap_name)

    snap_dir = Path(get_fs_mountpoint(fs)) / ".zfs/snapshot" / snap_name

    borg_env = make_borg_env(conf["repo"])

    # check if repo exists, create if not
    rinfo = borg_cmd("borg info", env=borg_env, check=False)
    if rinfo.returncode == 2:
        # repo dne, create
        logger.info(f"Creating new repo for {fs}")
        borg_cmd("borg init --encryption=repokey-blake2", env=borg_env)
    elif rinfo.returncode != 0:
        failexit(f"Unexpected return from borg info {rinfo.returncode}")

    # need to strip microseconds for borg
    dt = dt.replace(microsecond=0)
    opts = [
        "--exclude-caches",
        "--compression=zstd",
        f"--timestamp={dt.isoformat()}",
    ]

    if conf.get("exclude"):
        opts.extend(f"--exclude={e}" for e in conf["exclude"])

    logger.info(f"Backing up snapshot {snapshot}")

    opts = " ".join(opts)
    # archive name derived from snapshot tag (auto-<ISO_TIMESTAMP>)
    archive_name = f"{prefix}-{dt.isoformat()}"
    # Borg 1.x: use ::ARCHIVE shorthand, relying on BORG_REPO in env
    res = borg_cmd(f"borg create {opts} ::{archive_name} .", cwd=snap_dir, env=borg_env)
    logger.info(f"Output:\n{res.stdout}\n{res.stderr}")


# Main


def initial_setup(config: dict):
    global BORG_PASSPHRASE, BORG_KEYFILE_EXPORT_DIR

    # create or read passphrase
    pass_file = Path(config["borg_pass_file"]).expanduser()
    if not pass_file.is_file():
        logger.warning("Passphrase file not preset, creating new passphrase")
        BORG_PASSPHRASE = secrets.token_hex(16)
        pass_file.write_text(BORG_PASSPHRASE)
        pass_file.chmod(0o600)

    BORG_PASSPHRASE = pass_file.read_text()

    # create key export dir (even if not yet used)
    BORG_KEYFILE_EXPORT_DIR = Path(config["keyfile_export_dir"]).expanduser()
    BORG_KEYFILE_EXPORT_DIR.mkdir(exist_ok=True)


def perform_backups(config: dict, fs_conf: dict):
    fs = fs_conf["fs"]
    logger.info(f"Working on {fs}...")

    dt = datetime.now()
    snap = f"{AUTO_PREFIX}-{dt.isoformat()}"
    logger.info(f"Creating snapshot {fs}@{snap}")
    snapshot(fs, snap)

    # only consider auto snapshots we create
    snaps = [
        s for s in list_snapshots(fs) if s[s.index("@") + 1 :].startswith(AUTO_PREFIX)
    ]

    for snap in snaps:
        if not is_snapshot_backed_up(snap):
            do_backup(snap, fs_conf)
            mark_snapshot_backed_up(snap)

    logger.info(f"Cleaning snapshots for {fs}")

    for snap in snaps:
        _, snap_dt = parse_archive_tag(snap[snap.index("@") + 1 :])
        if dt - snap_dt > timedelta(days=config["keep_snapshot_days"]):
            logger.info(f"Dropping old snapshot {snap}")
            zfs_destroy(snap)

    borg_env = make_borg_env(fs_conf["repo"])

    logger.info(f"Borg prune for {fs}")
    day = config["day"]
    week = config["week"]
    month = config["month"]
    borg_cmd(
        f"borg prune --keep-daily={day} --keep-weekly={week} --keep-monthly={month}",
        env=borg_env,
    )

    logger.info(f"Borg compact {fs}")
    borg_cmd("borg compact", env=borg_env)

    logger.info(f"Finished {fs}")


def main(args):
    if not int(execute("id -u")):
        failexit("Don't as root!")

    # Note: log_file is taken from config, not the -l flag.
    if args.config.get("log_file"):
        fh = RotatingFileHandler(
            Path(args.config["log_file"]).expanduser(),
            maxBytes=int(1e6),
            backupCount=2,
        )
        fh.setFormatter(logging.Formatter(LOG_FMT))
        logger.addHandler(fh)

    borg_version = execute("borg --version").strip()
    logger.info(f"Borg version: {borg_version}")
    logger.info("Starting up...")

    initial_setup(args.config)

    for fs_conf in args.config["fs"].values():
        try:
            perform_backups(args.config, fs_conf)
        except Exception:
            logger.exception(f"{fs_conf['fs']} failed to back up! Moving on...")

    logger.info("Complete!")


def clean_snaps(args):
    for fs_conf in args.config["fs"].values():
        for snap in list_snapshots(fs_conf["fs"]):
            if input(f"Delete {snap}? (y/N) ").lower() == "y":
                zfs_destroy(snap)


if __name__ == "__main__":
    parser = argparse.ArgumentParser("Backups")
    parser.add_argument(
        "-l",
        "--log-file",
        type=lambda x: Path(x).expanduser(),
        default=Path.home() / "backups",
        help="Path to use for log file (rotated)",
    )
    parser.add_argument(
        "-c",
        "--config",
        type=lambda x: tomllib.load(Path(x).expanduser().open("rb")),
        default=tomllib.load((Path.home() / "backups/config.toml").open("rb")),
        help="Path to config file",
    )
    main(parser.parse_args())
