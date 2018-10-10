#!/usr/bin/env python3
import subprocess
import os

import requests


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
