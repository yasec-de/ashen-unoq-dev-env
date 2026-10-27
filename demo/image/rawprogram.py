#!/usr/bin/env python3
"""Point Arduino's rawprogram0.xml at the demo images.

Slot a gets the KVM pair (patched QHEE + EL2 U-Boot, which only work together); slot b keeps
the stock hyp.mbn/boot.img as a fallback. efi/rootfs/userdata get the images from mkimages.sh.
Writes rawprogram0.xml in place, keeping Arduino's original as rawprogram0.arduino.xml.
"""
import os
import shutil
import sys
import xml.etree.ElementTree as ET

flash = sys.argv[1]
src = os.path.join(flash, "rawprogram0.xml")
orig = os.path.join(flash, "rawprogram0.arduino.xml")
if not os.path.exists(orig):
    shutil.copy(src, orig)

files = {
    "hyp_a": "hyp-hvc.mbn",
    "boot_a": "boot-el2.img",
    "efi": "esp.img",
    "rootfs": "rootfs.img",
    "userdata": "userdata.img",
}
tree = ET.parse(orig)
seen = set()
for p in tree.getroot().iter("program"):
    label = p.get("label")
    if label not in files:
        continue
    name = files[label]
    size = os.path.getsize(os.path.join(flash, name))
    sectors = int(p.get("num_partition_sectors"))
    sector_size = int(p.get("SECTOR_SIZE_IN_BYTES"))
    # userdata is "rest of the disk" (0 sectors) in Arduino's table
    if sectors and size > sectors * sector_size:
        sys.exit(f"{name} ({size} bytes) does not fit {label} ({sectors * sector_size} bytes)")
    p.set("filename", name)
    p.set("sparse", "false")
    seen.add(label)
missing = set(files) - seen
if missing:
    sys.exit(f"partitions not found in rawprogram0.xml: {sorted(missing)}")
tree.write(src, xml_declaration=True, encoding="utf-8")
print(f"rawprogram0.xml: {', '.join(f'{k}={v}' for k, v in files.items())}")
