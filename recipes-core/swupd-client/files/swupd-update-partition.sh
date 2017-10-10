#!/bin/sh
#
# Ensures that an entire partition contains exactly the files from
# a certain OS build and nothing else.
# https://github.com/clearlinux/swupd-client/issues/249 explains
# the steps used by this script.
#
# There are some prerequisites for this script:
# - the current locale must support UTF-8 encoding because
#   currently unpacking files relies on that
#   (https://github.com/clearlinux/swupd-client/issues/280)
# - there must be enough space on the target partition for
#   the entire OS plus a compressed archive of the OS
#   (https://github.com/clearlinux/swupd-client/issues/285)
# - the swupd update repo must be available via http(s),
#   and connectivity should be good, because transient
#   network errors are not handled as well as they could
#   be (https://github.com/clearlinux/swupd-client/issues/292)
#
#
#      Copyright © 2017 Intel Corporation.
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, version 2 or later of the License.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -e

usage () {
    cat <<EOF
$0 -h|-p partition -m version -c contenturl [-f mkfscmd [-F]]

-h              help message
-p partition    full path to device entry for the target partition
-m version      OS version that needs to updated to
-c contenturl   full URL for the swupd update repo
-f mkfscmd      full command including the partition path that
                can be used to create a filesystem if needed
-F              always create a filesystem before installing

Ensures that an entire partition contains exactly the files from a
certain OS build and nothing else. Incremental updates are tried when
the content URL is exactly the same as the one for the current
partition content.
EOF
}

log () {
    echo "swupd-update-partition:" "$@"
}

execute () {
    log "$@"
    "$@"
}

PARTITION=
VERSION=
CONTENTURL=
MKFSCMD=
FORCE_MKFS=

while getopts ":hp:m:c:f:F" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        p)
            PARTITION="$OPTARG"
            ;;
        m)
            VERSION="$OPTARG"
            ;;
        c)
            CONTENTURL="$OPTARG"
            ;;
        f)
            MKFSCMD="$OPTARG"
            ;;
        F)
            FORCE_MKFS=1
            ;;
        \?)
            log "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            log "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

if ! [ "$PARTITION" ] || ! [ "$VERSION" ] || ! [ "$CONTENTURL" ]; then
    log "Partion (-p), version (-m), and content url (-c) must be specified." >&2
    exit 1
fi
if [ "$FORCE_MKFS" ] && ! [ "$MKFSCMD" ]; then
    log "Filesystem creation requested (-F) without also giving mkfs command (-f)." >&2
    exit
fi

MOUNTED=
MOUNTPOINT=
VERSIONDIR=
cleanup () {
    if [ "$MOUNTED" ]; then
        umount "$MOUNTPOINT"
    fi
    if [ "$MOUNTPOINT" ]; then
        rmdir "$MOUNTPOINT"
    fi
    if [ "$VERSIONDIR" ]; then
        rm -rf "$VERSIONDIR"
    fi
}
trap cleanup EXIT

MOUNTPOINT=$(mktemp -d)

# The swupd statedir only gets created once and then gets reused
# across different swupd invocations. The assumption is that swupd
# itself never corrupts its own state, thus allowing us to reuse
# already downloaded information. A more conservative approach would
# be to wipe out state before each invocation.
#
# The goal is to do this:
# STATEDIR=$(mktemp -d)
#
# In practice, the statedir currently has to be on the target
# partition, for two reason:
# - staging files happens under it and additional workarounds
#   would be needed to make rootfs construction work
#   without inefficient copying from the statedir to
#   the target partition (https://github.com/clearlinux/swupd-client/issues/273)
# - bsdtar fails to unpack Manifest.MoM.tar on tmpfs:
#   ioctl(4, FS_IOC_GETFLAGS, 0x7ffe5c46d874) = -1 ENOTTY (Inappropriate ioctl for device)
#   No bug filed at the moment.
#
# The downside is that currently the target partition must have
# enough extra space to store the pack .tar archives. See
# https://github.com/clearlinux/swupd-client/issues/285
STATEDIR="$MOUNTPOINT/swupd-state"

# "swupd verify" requires passing the format explicitly because it
# attempts to read from the target partition, which is either empty
# (swupd verify --install) or cannot be trusted to have the right
# format (swupd verify --fix).
SWUPDFORMAT=$(cat /usr/share/defaults/swupd/format)

# It would be nice if we could suppress the builtin post-update/verify
# hooks with --no-script, but right now swupd does not support that
# (see https://github.com/clearlinux/swupd-client/issues/286).
# SWUPSCRIPTS="--no-scripts"
SWUPDSCRIPTS=""

# The OS itself may have a /usr/share/defaults/swupd/contenturl file
# already, but it is not guaranteed to have the right URL. Therefore
# we write the current URL to a file that this script owns after each
# update.
CONTENTURLFILE="/.swupd-contenturl"

# We shouldn't need a version URL, but both "swupd update"
# and "swupd verify" currently expect it:
# - update: https://github.com/clearlinux/swupd-client/issues/257
# - verify: https://github.com/clearlinux/swupd-client/issues/277
#
# "swupd update" should take a "-m <numeric version>" number
# instead of always updating to the latest version.
#
# As a workaround, we create a fake version directory here
# and point to it with a file:// URL.
VERSIONDIR=$(mktemp -d)
mkdir -p "$VERSIONDIR/version/format$SWUPDFORMAT"
echo "$VERSION" >"$VERSIONDIR/version/format$SWUPDFORMAT/latest"
VERSIONURL="file://$VERSIONDIR"

main () {
    if doit; then
        log "Update successful."
    else
        log "Update failed."
        return 1
    fi
}

doit () {
    log "Updating to $VERSION from $CONTENTURL."
    if update_or_install; then
        if mkdir -p "$(dirname "$MOUNTPOINT/$CONTENTURLFILE")" &&
           echo "$CONTENTURL" > "$MOUNTPOINT/$CONTENTURLFILE" &&
           rm -rf "$STATEDIR" &&
           execute umount "$MOUNTPOINT"; then
            MOUNTED=
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Each of the following commands starts with nothing but the empty
# mount point and then tries to get the partition updated. They
# leave the target partition mounted for additional operations on
# it.

update_or_install () {
    if [ "$FORCE_MKFS" ]; then
        log "Reinstalling from scratch."
        format_and_install
    else
        log "Trying to update."
        # TODO: detect transient errors and give up early instead of
        # wiping out existing content (depends on
        # https://github.com/clearlinux/swupd-client/issues/292).
        if ! update; then
            if [ "$MKFSCMD" ]; then
                log "Updating failed, falling back to reinstalling from scratch."
                format_and_install
            else
                return 1
            fi
        fi
    fi
}

format_and_install () {
    if [ "$MOUNTED" ] && ! execute umount "$MOUNTPOINT"; then
        return 1
    fi
    log "Formatting partition."
    if execute $MKFSCMD &&
       execute mount "$PARTITION" "$MOUNTPOINT"; then
        MOUNTED=1
        log "Installing into empty partition."
        # TODO: do not run post-install hooks (https://github.com/clearlinux/swupd-client/issues/286)
        # Currently, systemd is restarted on the host and we get errors like this:
        # sh: /tmp/tmp.Jt0rVs//usr/bin/clr-boot-manager: No such file or directory
        execute swupd verify --install $SWUPDSCRIPTS -F $SWUPDFORMAT -c "$CONTENTURL" -v "$VERSIONURL" -m "$VERSION" -S "$STATEDIR" -p "$MOUNTPOINT"
    else
        return 1
    fi
}

update () {
    if execute mount "$PARTITION" "$MOUNTPOINT"; then
        MOUNTED=1
        # Don't trust existing leftover state on the partition. Merely a precaution.
        rm -rf "$STATEDIR"
        if [ -f "$MOUNTPOINT/$CONTENTURLFILE" ] &&
               [ "$(cat $MOUNTPOINT/$CONTENTURLFILE)" = "$CONTENTURL" ]; then
            log "Content URL unchanged, trying to update."
            # TODO: do not run post-install hooks (https://github.com/clearlinux/swupd-client/issues/286)
            if ! execute swupd update $SWUPDSCRIPTS -c "$CONTENTURL" -v "$VERSIONURL" -S "$STATEDIR" -p "$MOUNTPOINT"; then
                log "Incremental update failed, falling back to fixing content."
            fi
        else
            log "New content URL, falling back to fixing content."
        fi

        log "Verifying and fixing content."
        # TODO: clarify whether --picky is enough to get rid of all unwanted files
        # (https://github.com/clearlinux/swupd-client/issues/293).
        # TODO: do not run post-install hooks (https://github.com/clearlinux/swupd-client/issues/286)
        execute swupd verify --fix --picky $SWUPDSCRIPTS -F $SWUPDFORMAT -c "$CONTENTURL" -v "$VERSIONURL" -m "$VERSION" -S "$STATEDIR" -p "$MOUNTPOINT"
    else
        return 1
    fi
}

main
