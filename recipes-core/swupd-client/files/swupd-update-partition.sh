#!/bin/sh
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
#   and connectivity should be good; loss of network activity
#   will be detected
#
# The script returns with the following codes:
# 0 = success
# 1 = permanent failure, retrying probably won't help
# 2 = temporary network failure, can be tried again later
#
# "set -e" is not used intentionally, instead relying on explicit
# error checking.

EXIT_SUCCESS=0
EXIT_FAILURE=1
EXIT_NETWORK=2

usage () {
    cat <<EOF
$0 -h|-p partition -m version -c contenturl [-f mkfscmd [-F]] [-s source]

-h              help message
-p partition    full path to device entry for the target partition
-m version      OS version that needs to updated to
-c contenturl   full URL for the swupd update repo
-f mkfscmd      full command including the partition path that
                can be used to create a filesystem if needed
-F              always create a filesystem before installing
-s source       will be copied over to the target partition file-by-file
                before updating the target partition; can be a block device
                which will be mounted or an already mounted filesystem
                path which will be bind-mounted

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

execute_swupd () {
    # This is the only place were we use the network, and thus here
    # we can exit early when there are network issues.
    execute swupd "$@"
    swupd_result=$?

    # swupd has certain undocumented return codes. We can rely on
    # those already, but further work is needed
    # (https://github.com/clearlinux/swupd-client/issues/296).
    # For example, 404 cannot really be returned in practice.
    #
    # This list is from https://github.com/clearlinux/swupd-client/blob/22cccd9a045a2615a4b727afa9ed4ea3e39f8010/include/swupd-error.h
    case $swupd_result in
        0) : ;;
        1) log "swupd: return code 1 = unspecific failure";;
        2) log "swupd: EBUNDLE_MISMATCH = $swupd_result = at least one local bundle mismatches from MoM";;
        3) log "swupd: EBUNDLE_REMOVE = $swupd_result = cannot delete local bundle filename";;
        4) log "swupd: EMOM_NOTFOUND = $swupd_result = MoM cannot be loaded into memory (this could imply network issue)"
            exit_network
            ;;
        5) log "swupd: ETYPE_CHANGED_FILE_RM = $swupd_result = do_staging() couldn't delete a file which must be deleted";;
        6) log "swupd: EDIR_OVERWRITE = $swupd_result = do_staging() couldn't overwrite a directory";;
        7) log "swupd: EDOTFILE_WRITE = $swupd_result = do_staging() couldn't create a dotfile";;
        8) log "swupd: ERECURSE_MANIFEST = $swupd_result = error while recursing a manifest";;
        9) log "swupd: ELOCK_FILE = $swupd_result = cannot get the lock";;
        10) log "swupd: EPREP_MOUNT = $swupd_result = failed to prepare mount points";;
        11) log "swupd: ECURL_INIT = $swupd_result = cannot initialize curl agent";;
        12) log "swupd: EINIT_GLOBALS = $swupd_result = cannot initialize globals";;
        13) log "swupd: EBUNDLE_NOT_TRACKED = $swupd_result = bundle is not tracked on the system";;
        14) log "swupd: EMANIFEST_LOAD = $swupd_result = cannot load manifest into memory";;
        15) log "swupd: EINVALID_OPTION = $swupd_result = invalid command option";;
        16) log "swupd: ENOSWUPDSERVER = $swupd_result = no net connection to swupd server";;
        17) log "swupd: EFULLDOWNLOAD = $swupd_result = full_download problem";;
        404) log "swupd: ENET404 = $swupd_result = download 404'd"
            exit_network
            ;;
        18) log "swupd: EBUNDLE_INSTALL = $swupd_result = Cannot install bundles";;
        19) log "swupd: EREQUIRED_DIRS = $swupd_result = Cannot create required dirs";;
        20) log "swupd: ECURRENT_VERSION = $swupd_result = Cannot determine current OS version";;
        21) log "swupd: ESIGNATURE = $swupd_result = Cannot initialize signature verification";;
        22) log "swupd: EBADTIME = $swupd_result = System time is bad";;
        23) log "swupd: EDOWNLOADPACKS = $swupd_result = Pack download failed"
            exit_network
            ;;
        *) log "swupd: unknown return code $swupd_result";;
    esac
    return $swupd_result
}

exit_network () {
    log "Update failed temporarily."
    exit $EXIT_NETWORK
}

PARTITION=
VERSION=
CONTENTURL=
MKFSCMD=
FORCE_MKFS=
SOURCE=

while getopts ":hp:m:c:f:Fs:" opt; do
    case $opt in
        h)
            usage
            exit $EXIT_SUCCESS
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
        s)
            SOURCE="$OPTARG"
            ;;
        \?)
            log "Invalid option: -$OPTARG" >&2
            exit $EXIT_FAILURE
            ;;
        :)
            log "Option -$OPTARG requires an argument." >&2
            exit $EXIT_FAILURE
            ;;
    esac
done

if ! [ "$PARTITION" ] || ! [ "$VERSION" ] || ! [ "$CONTENTURL" ]; then
    log "Partion (-p), version (-m), and content url (-c) must be specified." >&2
    exit $EXIT_FAILURE
fi
if [ "$FORCE_MKFS" ] && ! [ "$MKFSCMD" ]; then
    log "Filesystem creation requested (-F) without also giving mkfs command (-f)." >&2
    exit $EXIT_FAILURE
fi

MOUNTED=
MOUNTPOINT=
MOUNTED_SOURCE=
MOUNTPOINT_SOURCE=
VERSIONDIR=
cleanup () {
    if [ "$MOUNTED" ]; then
        umount "$MOUNTPOINT"
    fi
    if [ "$MOUNTPOINT" ]; then
        rmdir "$MOUNTPOINT"
    fi
    if [ "$MOUNTED_SOURCE" ]; then
        umount "$MOUNTPOINT_SOURCE"
    fi
    if [ "$MOUNTPOINT_SOURCE" ]; then
        rmdir "$MOUNTPOINT_SOURCE"
    fi
    if [ "$VERSIONDIR" ]; then
        rm -rf "$VERSIONDIR"
    fi
}
trap cleanup EXIT

MOUNTPOINT=$(mktemp -t -d swupd-mount.XXXXXX)
if [ "$SOURCE" ]; then
    if ! MOUNTPOINT_SOURCE=$(mktemp -t -d swupd-mount-source.XXXXXX); then
        return 1
    fi
    if [ -b "$SOURCE" ]; then
        log "Mounting source partition."
        if ! execute mount -oro "$SOURCE" "$MOUNTPOINT_SOURCE"; then
            return 1
        fi
    else
        log "Bind-mounting source tree."
        if ! execute mount -obind,ro "$SOURCE" "$MOUNTPOINT_SOURCE"; then
            return 1
        fi
    fi
    MOUNTED_SOURCE=1
fi


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
STATEDIR_RELATIVE="swupd-state"
STATEDIR="$MOUNTPOINT/$STATEDIR_RELATIVE"

# "swupd verify" requires passing the format explicitly because it
# attempts to read from the target partition, which is either empty
# (swupd verify --install) or cannot be trusted to have the right
# format (swupd verify --fix).
SWUPDFORMAT=$(cat /usr/share/defaults/swupd/format)

# Suppress all the usual post-update hooks (like restarting systemd)
# because they don't make sense when not updating the currently
# running OS.
SWUPDSCRIPTS="--no-scripts"

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
VERSIONDIR=$(mktemp -t -d swupd-version.XXXXXX)
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
        # Explicitly check the unmount result to ensure that the final
        # write succeeds.
        if execute umount "$MOUNTPOINT"; then
            MOUNTED=
            sync
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
        if ! mount_and_update; then
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
        # We remove lost+found here because it is not tracked by swupd
        # and thus would get removed by "swupd verify --fix" anyway
        # (see below). It gets re-created by mkfs.ext4 when checking the
        # file system, should that ever get done.
        execute rm -rf "$MOUNTPOINT/lost+found"
        if [ "$SOURCE" ]; then
            copy_from_source && update
        else
            log "Installing into empty partition."
            execute_swupd verify --install $SWUPDSCRIPTS -F $SWUPDFORMAT -c "$CONTENTURL" -v "$VERSIONURL" -m "$VERSION" -S "$STATEDIR" -p "$MOUNTPOINT"
        fi
    else
        return 1
    fi
}

mount_and_update () {
    if execute mount "$PARTITION" "$MOUNTPOINT"; then
        MOUNTED=1
        if [ "$SOURCE" ] && ! copy_from_source; then
            return 1
        fi
        update
    else
        return 1
    fi
}

update () {
    # Don't trust existing leftover state on the partition. Merely a precaution.
    rm -rf "$STATEDIR"
    log "Trying to update."
    if ! execute_swupd update $SWUPDSCRIPTS -c "$CONTENTURL" -v "$VERSIONURL" -S "$STATEDIR" -p "$MOUNTPOINT"; then
        log "Incremental update failed, falling back to fixing content."
    fi

    # There are several reasons why we explicitly do a "verify --fix":
    # - Updating from one update stream to another, unrelated one may have succeeded without actually fully
    #   updating the system.
    # - "swupd update" does not remove extra files that might have been copied unnecessarily
    #   from the source partition.
    # - "swupd verify" checks file integrity.
    #
    # We use --extra-picky, which covers the entire file system and thus will also remove
    # "lost+found" and any leftover files which might be stored in it.
    log "Verifying and fixing content."
    execute_swupd verify --fix --extra-picky --picky-whitelist ^/$STATEDIR_RELATIVE/ $SWUPDSCRIPTS -F $SWUPDFORMAT -c "$CONTENTURL" -v "$VERSIONURL" -m "$VERSION" -S "$STATEDIR" -p "$MOUNTPOINT"
}

copy_from_source () {
    # Create a union of current content on target and source partitions.
    # Files are intentionally not deleted on the target because they might
    # re-appear during an update. swupd will delete them if they don't.
    # The downside of this approach is slightly higher disk overhead and
    # potentially copying of files that are not needed after all.
    #
    # We could do this with rsync:
    # execute rsync --archive --hard-links --xattrs --acls --devices --specials --super $MOUNTPOINT_SOURCE/ $MOUNTPOINT/
    #
    # However, rsync would be another external dependency. We can do the same
    # with bsdtar by copying new or newer (in terms of modification time stamp) files
    # from the source to the target partition after ensuring that the target
    # can be created by deleting any old content under the same name.
    #
    # The modification time stamps should be preserved by image
    # creation and swupd. Directories and symlinks only get copied if
    # they don't exist. That leaves fixing up permissions or symlink
    # content to swupd.
    #
    # We copy everything. This only works well when the majority
    # (all?!) of the writable data is elsewhere, otherwise we end up
    # copying data that just ends up getting removed again by "swupd
    # verify --fix --extra-picky".
    log "Copy from source $SOURCE."
    itemlist="$MOUNTPOINT/swupd-copy-from-source"
    (cd $MOUNTPOINT_SOURCE && find . -path ./lost+found -prune -o \( -type d -o -type f -o -type l \) -print |
                while read -r item; do
                    if [ -h "$MOUNTPOINT/$item" ]; then
                        if [ -h "$item" ] && [ "$(readlink "$item")" = "$(readlink "$MOUNTPOINT/$item")" ]; then
                            # Symlinks identical, keep them.
                            continue
                        fi
                    elif [ -d "$MOUNTPOINT/$item" ]; then
                        if [ -d "$item" ]; then
                            # Don't try to unpack a directory on top
                            # of another.  If permissions are
                            # different, swupd will have to fix them.
                            continue
                        fi
                    elif [ -f "$MOUNTPOINT/$item" ]; then
                        if [ -f "$MOUNTPOINT/$item" ] && ! [ "$MOUNTPOINT/$item" -ot "$item"  ]; then
                            # Target file is not older (usually same age or perhaps newer), keep it.
                            continue
                        fi
                    fi
                    # Remove old entry, whatever it is, so that it can be replaced.
                    rm -rf "$MOUNTPOINT/$item"
                    echo "$item"
                done ) > "$itemlist"
    bsdtar -ncf - -T "$itemlist" -C "$MOUNTPOINT_SOURCE" | bsdtar -xf - -C "$MOUNTPOINT"
    rm "$itemlist"

    # Don't fail when copying something didn't work.
    # The code above nevertheless checks for the copy_from_source
    # return code, so we could indicate fatal errors if we wanted to.
    return 0
}

if main; then
    exit $EXIT_SUCCESS
else
    exit $EXIT_FAILURE
fi
