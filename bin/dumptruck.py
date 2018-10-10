#!/usr/bin/env python3
import time
import json
import os
import os.path
import subprocess
import sys
from glob import glob

import requests

import swift
import rclone


def backup_all(encryption, sources, storage, monitor=None):
    for source in sources:
        try:
            backup(encryption, source, storage)
            if monitor:
                notify(source, **monitor)

        # Catch all so that one failed backup doesn't stop all others from happening
        except Exception as e:
            print("Backup failed with:", e)

        finally:
            remove_files()


def backup(encryption, source, storage):
    path = dump(encryption, **source)

    for store in storage:
        if store["type"] == "swift":
            token = swift.auth(**store)
            swift.upload(path, token, store["container_url"])
            swift.cleanup(path, token, store["container_url"], source["keep"])
        else:
            rclone.upload(path, store["remote"], store["target"])
            rclone.cleanup(path, store["remote"], store["target"], source["keep"])


def dump(encryption, dbtype, host, username, password, database, name=None, tunnel=None, **_):
    timestamp = time.strftime("%Y%m%d-%H%M", time.gmtime())

    path = ".".join((name, timestamp, "gz.enc"))

    root = os.path.dirname(os.path.realpath(__file__))
    cmd = [root + "/dump.sh", dbtype, host, username, password, database, path, encryption]
    if tunnel:
        cmd.append(tunnel)

    subprocess.check_call(cmd)
    return path


def remove_files():
    for path in glob("*.gz.enc"):
        os.remove(path)


def notify(source, username, password, url):
    source = dict(source)
    source.setdefault("database", "")
    data = "\n".join((
        '# TYPE backup_time_seconds gauge',
        '# HELP backup_time_seconds Last Unix time when this source was backed up.',
        'backup_time_seconds {time}\n'.format(time=time.time())
    ))
    url = "{root}/metrics/job/dumptruck/instance/{name}".format(root=url, **source)
    resp = requests.post(url, data=data, auth=requests.auth.HTTPBasicAuth(username, password))
    print(resp.text)


def main():
    path = sys.argv[1]
    with open(path) as f:
        config = json.load(f)
        backup_all(**config)


if __name__ == "__main__":
    main()
