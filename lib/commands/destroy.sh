#!/bin/bash
set -e

# command boilerplate
BASE_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" && pwd )"
CMD_PATH="${BASH_SOURCE[0]}"
source $BASE_PATH/lstack.sh

check_distro
needs_root

if ! lxc-ls -1 |grep ^$LSTACK_NAME >/dev/null 2>&1; then
  error "$LSTACK_NAME container not available"
  exit 1
fi

# FIXME: not sure if this is actually required or if there's faster and
# equaly safe way.
# If the container is stopped, we need to boot it to clean the
# volume group and the loop device.
if lxc-info -n "$LSTACK_NAME" | grep STOPPED >/dev/null; then
  warn "Container stopped. Booting it to clean it up."
  lxc-start -n "$LSTACK_NAME" -d
  wait_for_container_ip
fi

# make sure the required kernel modules are loaded
debug "Loading required kernel modules"
modprobe nbd
modprobe ebtables

# We need to destroy the instances in case they have Cinder volumes
# attached. Otherwise we won't be able to remove the LVM volume group
# and the loopback device.
if [ -f $LSTACK_ROOTFS/root/creds.sh ]; then
  debug "Destroying instances"
  destroy_instances
else
  warn "OpenStack credentials not found. Won't destroy the instances (if any)"
fi


# Destroy the Volume Group used for Cinder
debug "Destroy the volume group $LSTACK_NAME-vg"
if [ -d "$LSTACK_ROOTFS/dev/$LSTACK_NAME-vg" ]; then
  cexe "$LSTACK_NAME" "vgremove -f $LSTACK_NAME-vg" > /dev/null 2>&1
fi

debug "Cleanup the loop device"
# if the loop device isn't found we don't need to delete it
__loopdev=$(losetup -a | grep $LSTACK_NAME-vg 2>/dev/null | cut -d: -f1)
if [ -n "$__loopdev" ]; then
  losetup -d "$__loopdev" || {
    error "Could not cleanup loop device. Aborting."
    exit 1
  }
fi

info "Destroying the container..."
lxc-destroy -n $LSTACK_NAME -f
