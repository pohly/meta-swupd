# Class for swupd client integration -- adds necessary bits to
# rootfs images that contain the swupd-client, i.e. setting the
# expected format version, URLs, and public keys.
#
# Usage:
# * inherit this class if you wish to create an image that contains the
#   swupd-client, but where the image itself is not subject to any
#   swupd based processing
#
# An example would be an initramfs that contains the client, but that
# initramfs itself is a regular file in a different (outer) file system
# (image). The outer image would be subject to swupd processing, and the
# inner initramfs is simply responsible to update the outer file system
# during system (re)start.

require conf/swupd/swupd-config.inc

PACKAGE_INSTALL_append = " swupd-client-format${SWUPD_TOOLS_FORMAT}"

# swupd-client checks VERSION_ID, which must match the OS_VERSION
# used for generating swupd bundles in the current build.
#
# We patch this during image creation and exclude OS_VERSION from the
# dependencies because doing it during the compilation of os-release.bb
# would trigger a rebuild even if all that changed is the OS_VERSION.
# It would also affect builds of images where swupd is not active. Both
# is undesirable.
#
# If triggering a rebuild on each OS_VERSION change is desired,
# then this can be achieved by influencing the os-release package
# by setting in local.conf:
# VERSION_ID = "${OS_VERSION}"
PACKAGE_INSTALL_append = " os-release"
swupd_patch_os_release () {
    sed -i -e 's/^VERSION_ID *=.*/VERSION_ID="${OS_VERSION}"/' ${IMAGE_ROOTFS}/usr/lib/os-release
}
swupd_patch_os_release[vardepsexclude] = "OS_VERSION"
ROOTFS_POSTPROCESS_COMMAND += "swupd_patch_os_release; "

# swupd-client's verifytime command relies on /usr/share/clear/versionstamp
# containing the seconds since the epoch when the image was created.
python swupd_create_versionstamp () {
    import time
    dir = d.getVar('IMAGE_ROOTFS', True) + '/usr/share/clear'
    bb.utils.mkdirhier(dir)
    with open(dir + '/versionstamp', 'w') as f:
        f.write('%d' % time.time())
}
ROOTFS_POSTPROCESS_COMMAND += "swupd_create_versionstamp; "

def hash_swupd_pinned_pubkey(d):
    pubkey = d.getVar('SWUPD_PINNED_PUBKEY', True)
    if pubkey:
        import hashlib
        bb.parse.mark_dependency(d, pubkey)
        with open(pubkey, 'rb') as f:
            hash = hashlib.sha256()
            hash.update(f.read())
            return hash.hexdigest()
    else:
        return ''

SWUPD_PINNED_PUBKEY_HASH := "${@ hash_swupd_pinned_pubkey(d)}"

# The swupd client must be configured on a per-image basis.
# Different images might need different settings.
configure_swupd_client () {
    # Write default values to the configuration hierarchy (since 3.4.0)
    install -d ${IMAGE_ROOTFS}/usr/share/defaults/swupd
    if [ "${SWUPD_VERSION_URL}" ]; then
        echo "${SWUPD_VERSION_URL}" >> ${IMAGE_ROOTFS}/usr/share/defaults/swupd/versionurl
    fi
    if [ "${SWUPD_CONTENT_URL}" ]; then
        echo "${SWUPD_CONTENT_URL}" >> ${IMAGE_ROOTFS}/usr/share/defaults/swupd/contenturl
    fi
    echo "${SWUPD_FORMAT}" >> ${IMAGE_ROOTFS}/usr/share/defaults/swupd/format
    # Changing content of the pubkey also changes the hash and thus ensures
    # that this method and thus do_rootfs run again.
    #
    # TODO: does not actually work. Recipe gets reparsed when the file
    # changes ("bitbake -e ostro-image-swupd | SWUPD_PINNED_PUBKEY_HASH" changes)
    # but the task  does not get re-executed. Forcing that leads to:
    #
    # ERROR: ostro-image-swupd-1.0-r0 do_rootfs: Taskhash mismatch 8762bf20b997ac29dd6793fd11e609c3 versus cb40afac8ca291e31022d5ffd9a9bbac for /work/ostro-os/meta-ostro/recipes-image/images/ostro-image-swupd.bb.do_rootfs
    # ERROR: Taskhash mismatch 8762bf20b997ac29dd6793fd11e609c3 versus cb40afac8ca291e31022d5ffd9a9bbac for /work/ostro-os/meta-ostro/recipes-image/images/ostro-image-swupd.bb.do_rootfs
    #
    # $ bitbake-diffsigs tmp-glibc/stamps/qemux86-ostro-linux/ostro-image-swupd/1.0-r0.do_rootfs.sigdata.c8a9371831f58ce4f8b49a73211f66aa tmp-glibc/stamps/qemux86-ostro-linux/ostro-image-swupd/1.0-r0.do_rootfs.sigdata.cb40afac8ca291e31022d5ffd9a9bbac
    # basehash changed from 02de100ee7baa348e224f21844fdaa06 to e3bb23a069673a09afee4994522991d3
    # Variable SWUPD_PINNED_PUBKEY_HASH value changed from 'b9ffbe0963f3f7ab3f3c1af5cd8471c121cb601eb4294ad4b211f1e206746a0a' to '8d172423eb0162feb8c7fb2f2d7da28a6effdf3e95184114c62e6b0efdeae89a'
    # Taint (by forced/invalidated task) changed from None to 2c8e3b43-5e70-4c96-bf6e-741f0b344731
    #
    # There's no sigdata for 8762b. c8a93 is from before changing the file.
    if [ "${SWUPD_PINNED_PUBKEY_HASH}" ]; then
        install -d ${IMAGE_ROOTFS}${datadir}/clear/update-ca
        install -m 0644 '${SWUPD_PINNED_PUBKEY}' ${IMAGE_ROOTFS}${datadir}/clear/update-ca/
        echo "${datadir}/clear/update-ca/$(basename '${SWUPD_PINNED_PUBKEY}')" > ${IMAGE_ROOTFS}/usr/share/defaults/swupd/pinnedpubkey
    fi
    chown -R root:root ${IMAGE_ROOTFS}/usr/share/defaults/swupd
    chmod 0644 ${IMAGE_ROOTFS}/usr/share/defaults/swupd/*
}
ROOTFS_POSTPROCESS_COMMAND_append = " configure_swupd_client;"
