#!/usr/bin/env python3
import time
import json
import os
import os.path
import subprocess
import sys
from glob import glob

import requests


def backup_all(encryption, sources, storage, monitor):
    for source in sources:
        try:
            backup(encryption, source, storage)
            notify(source, **monitor)

        # Catch all so that one failed backup doesn't stop all others from happening
        except Exception as e:
            print("Backup failed with:", e)

        finally:
            remove_files()


def backup(encryption, source, storage):
    path = dump(encryption, **source)

    for store in storage:
        token = auth(**store)
        upload(path, token, store["container_url"])
        cleanup(path, token, store["container_url"], source["keep"])


def dump(encryption, dbtype, host, username, password, database, name=None, tunnel=None, **_):
    timestamp = time.strftime("%Y%m%d-%H%M", time.gmtime())

    path = ".".join((name, timestamp, "gz.enc"))

    root = os.path.dirname(os.path.realpath(__file__))
    cmd = [root + "/dump.sh", dbtype, host, username, password, database, path, encryption]
    if tunnel:
        cmd.append(tunnel)

    subprocess.check_call(cmd)
    return path


def upload(path, token, container_url):
    checksum = subprocess.check_output(["md5sum", path]).split()[0].decode()
    res = put_object("/".join((container_url, path)), path, checksum, token)
    if res.status_code != 201:
        raise ValueError()


def cleanup(path, token, container_url, keep):
    prefix = ".".join(path.split(".")[0:-3])
    backups = get_objects(container_url, token)
    backups = sorted(b for b in backups if b.startswith(prefix))

    to_delete = backups[0:-keep]
    for obj in to_delete:
        res = delete_object("/".join((container_url, obj)), token)
        if res.status_code != 204:
            raise ValueError("Unexcpected status {}.".format(res.status))


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


def auth(auth_url, username, password, project_id, user_domain_id, **_):
    payload = {
        "auth": {
            "identity": {
                "methods": ["password"],
                "password": {
                    "user": {
                        "name": username,
                        "domain": {"id": user_domain_id},
                        "password": password
                    }
                }
            },
            "scope": {
                "project": {
                    "id": project_id
                }
            }
        }
    }
    url = auth_url + "/auth/tokens"
    res = requests.post(url, json=payload)
    return res.headers["X-Subject-Token"]


def put_object(url, path, checksum, token):
    headers = {
        "X-Auth-Token": token,
        "ETag": checksum,
        "Content-Length": str(os.path.getsize(path))
    }
    with open(path, "rb") as f:
        return requests.put(url, data=f, headers=headers)

def get_objects(url, token):
    headers = {
        "X-Auth-Token": token
    }
    res = requests.get(url, headers=headers)
    return res.text.split("\n")

def delete_object(url, token):
    headers = {
        "X-Auth-Token": token
    }
    return requests.delete(url, headers=headers)


def main():
    path = sys.argv[1]
    with open(path) as f:
        config = json.load(f)
        backup_all(**config)


if __name__ == "__main__":
    main()
