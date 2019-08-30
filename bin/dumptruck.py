#!/usr/bin/env python3
import time
import json
import os
import os.path
import subprocess
import sys
import traceback
from glob import glob

import requests

import swift
import rclone


ROOT = os.path.dirname(os.path.realpath(__file__))
DUMP = ROOT + "/dump.sh"

def backup_all(encryption, sources, storage, monitor=None):
    for source in sources:
        try:
            print("Backing up", source["name"], "...")
            backup(encryption, source, storage)
            if monitor:
                notify_success(source, **monitor)

        # Catch all so that one failed backup doesn't stop all others from happening
        except Exception as e:
            print("Backup failed with:", e)
            notify_failure(source, **monitor)
            traceback.print_exc()

        finally:
            remove_files()


def backup(encryption, source, storage):
    path = dump(encryption, source)
    print("Backup completed:", path)

    for store in storage:
        if store["type"] == "swift":
            token = swift.auth(**store)
            swift.upload(path, token, store["container_url"])
            swift.cleanup(path, token, store["container_url"], source["keep"])
        elif store["type"] == "rclone":
            rclone.upload(path, store["remote"], store["target"])
            rclone.cleanup(path, store["remote"], store["target"], source["keep"])


def dump_other(encryption, dbtype, host, username, password, database, name=None, tunnel="", **_):
    timestamp = time.strftime("%Y%m%d-%H%M", time.gmtime())

    path = ".".join((name, timestamp, "gz.enc"))

    cmd = [DUMP, "dump_other", dbtype, host, username, password, database, path, encryption, tunnel]

    subprocess.check_call(cmd)
    return path

def dump_ravendb(encryption, timestamp, url, cert, key, database, name, collections=None, **_):
    path = ".".join((name, timestamp, "ravendbdump.enc"))
    params = [url, cert, key, database, json.dumps(collections), path, encryption]

    cmd = [DUMP, "dump_ravendb", *params]
    subprocess.check_call(cmd)

    return path

def dump(encryption, source):
    timestamp = time.strftime("%Y%m%d-%H%M", time.gmtime())
    dbtype = source["dbtype"]

    if dbtype == "ravendb":
        return dump_ravendb(encryption, timestamp, **source)

    return dump_other(encryption, **source)


def remove_files():
    for path in glob("*.enc"):
        os.remove(path)


def notify(source, username, password, url, data):
    url = "{root}/metrics/job/dumptruck/instance/{name}".format(root=url, **source)
    resp = requests.post(url, data=data, auth=requests.auth.HTTPBasicAuth(username, password))
    print(resp.text)

def notify_success(source, username, password, url):
    source = dict(source)
    source.setdefault("database", "")
    data = "\n".join((
        '# TYPE backup_time_seconds gauge',
        '# HELP backup_time_seconds Last Unix time when this source was backed up.',
        'backup_time_seconds{{database="{database}",type="{dbtype}"}} {time}\n'
        '# TYPE backup_status gauge',
        '# HELP backup_status Indicates success/failure of the last backup attempt.',
        'backup_status{{database="{database}",type="{dbtype}"}} 1\n'
    )).format(database=source["database"], dbtype=source["dbtype"], time=time.time())
    notify(source, username, password, url, data)

def notify_failure(source, username, password, url):
    source = dict(source)
    source.setdefault("database", "")

    data = "\n".join((
        '# TYPE backup_status gauge',
        '# HELP backup_status Indicates success/failure of the last backup attempt.',
        'backup_status{{database="{database}",type="{dbtype}"}} -1\n'
    )).format(database=source["database"], dbtype=source["dbtype"])
    notify(source, username, password, url, data)

def restore(name, file, encryption, sources, storage, **_):
    for s in sources:
        if s["name"] == name:
            source = s
            break
    else:
        print("No database '{}' in config.".format(name))
        return

    for store in storage:
        try:
            if store["type"] == "swift":
                token = swift.auth(**store)
                swift.save_object(token, store["container_url"], file, ".")
            elif store["type"] == "rclone":
                rclone.save_object(store["remote"], store["target"], file, ".")
            else:
                continue
            break
        except Exception as e:
            print("Failed to get {} with error:", e)
            continue
    else:
        print("Backup could not be retrieved, aborting restore.")

    dbtype = source["dbtype"]

    if dbtype == "ravendb":
        return restore_ravendb(file, encryption, **source)

    return restore_other("./" + file, encryption, **source)


def restore_other(path, encryption, dbtype, host, username, password, database, tunnel=None, **_):
    cmd = [DUMP, "restore_other", dbtype, host, username, password, database, path, encryption]
    if tunnel:
        cmd.append(tunnel)
    subprocess.check_call(cmd)

    remove_files()


def restore_ravendb(path, encryption, url, cert, key, database, tunnel=None, **_):
    cmd = [DUMP, "restore_ravendb", url, cert, key, database, path, encryption]
    if tunnel:
        cmd.append(tunnel)
    subprocess.check_call(cmd)

    remove_files()


def main():
    path = sys.argv[1]
    with open(path) as f:
        config = json.load(f)

    if len(sys.argv) == 2:
        backup_all(**config)

    elif len(sys.argv) == 3:
        name = sys.argv[2]
        config["sources"] = list(filter(lambda x: x["name"] == name, config["sources"]))
        backup_all(**config)

    elif len(sys.argv) == 4:
        name = sys.argv[2]
        dump = sys.argv[3]
        restore(name, dump, **config)

    else:
        print(
            "Usage: {} <config.json>  perform database backups according to <config.json>\n",
            "or     {} <config.json> <source_name> perform a single database backup according to <config.json>\n",
            "or     {} <config.json> <source_name> <dump>  takes settings from <config.json> and downloads <dump> from a storage provider and tries to restore it to the database with name <source>"
        )


if __name__ == "__main__":
    main()
