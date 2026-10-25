"""Erase radon's agent disk into one APFS volume named Agent.

The disk is found by the USB serial number that hosts/radon.nix declares, so
no other disk can be erased. Without --erase the command only shows the disk.
A disk that already holds an APFS container is refused: that is the Agent
volume this command made.
"""

import argparse
import plistlib
import subprocess
import sys

DISKUTIL = "/usr/sbin/diskutil"


def plist(*command):
    run = subprocess.run(command, capture_output=True, check=True)
    return plistlib.loads(run.stdout)


def children(entry):
    return entry.get("IORegistryEntryChildren", [])


def usb_device(entry, serial):
    if entry.get("USB Serial Number") == serial:
        return entry
    found = (usb_device(child, serial) for child in children(entry))
    return next(filter(None, found), None)


def whole_disk(entry):
    if entry.get("Whole") is True and "BSD Name" in entry:
        return entry["BSD Name"]
    return next(filter(None, map(whole_disk, children(entry))), None)


def disk_with_serial(serial):
    ioreg = ("/usr/sbin/ioreg", "-a", "-l", "-r", "-c", "IOUSBHostDevice")
    for root in plist(*ioreg):
        device = usb_device(root, serial)
        if device:
            return whole_disk(device)
    return None


def apfs_containers(disk):
    containers = plist(DISKUTIL, "apfs", "list", "-plist")["Containers"]
    return [
        container
        for container in containers
        if any(
            store["DeviceIdentifier"].startswith(disk + "s")
            for store in container["PhysicalStores"]
        )
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("serial", help="USB serial number of the agent disk")
    parser.add_argument(
        "--erase", action="store_true", help="erase the disk; without it, only show it"
    )
    args = parser.parse_args()

    disk = disk_with_serial(args.serial)
    if disk is None:
        sys.exit(f"agent-volume-format: no disk with USB serial {args.serial} is attached")
    subprocess.run([DISKUTIL, "list", disk], check=True)
    if apfs_containers(disk):
        sys.exit(
            f"agent-volume-format: {disk} already holds an APFS container; "
            "erase it by hand if that is really meant"
        )
    if not args.erase:
        print(f"agent-volume-format: --erase erases {disk} into one APFS volume named Agent")
        return

    subprocess.run([DISKUTIL, "eraseDisk", "APFS", "Agent", "GPT", disk], check=True)
    (volume,) = [
        volume
        for container in apfs_containers(disk)
        for volume in container["Volumes"]
        if volume["Name"] == "Agent"
    ]
    print(
        f'Set agentVolumeUUID = "{volume["APFSVolumeUUID"]}"; in hosts/radon.nix and '
        "switch. agent-volume-unlock then encrypts the volume with "
        "/etc/hermes/agent-volume.key."
    )


if __name__ == "__main__":
    main()
