import subprocess

def upload(path, remote, target):
    cmd = ["rclone", "--config", "rclone", "copy", path, ":".join((remote, target))]
    subprocess.check_call(cmd)

def cleanup(path, remote, target, keep):
    prefix = ".".join(path.split(".")[0:-3])
    backups = get_objects(remote, target)
    backups = sorted(b for b in backups if b.startswith(prefix))
    to_delete = backups[0:-keep]
    for obj in to_delete:
        delete_object(remote, target, obj)

def get_objects(remote, target):
    cmd = ["rclone", "--config", "rclone", "lsf", ":".join((remote, target))]
    objects = subprocess.check_output(cmd).split()
    return (o.decode() for o in objects)

def delete_object(remote, target, obj):
    path = "{}:{}/{}".format(remote, target, obj)
    cmd = ["rclone", "--config", "rclone", "delete", path]
    subprocess.check_call(cmd)

def save_object(remote, target, obj, dest):
    path = "{}:{}/{}".format(remote, target, obj)
    cmd = ["rclone", "--config", "rclone", "copy", path, dest]
    subprocess.check_call(cmd)
