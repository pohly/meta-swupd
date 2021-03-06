SUMMARY = "swupd sofware update from Clear Linux - server component"
HOMEPAGE = "https://github.com/clearlinux/swupd-server"
LICENSE = "GPL-2.0"
LIC_FILES_CHKSUM = "file://COPYING;md5=f8d90fb802930e30e49c39c8126a959e"

DEPENDS = "file glib-2.0 rsync openssl libarchive curl bsdiff bzip2"
# Need the special "-replacement" variant because bzip2 and file
# are assumed to be provided and would not get built.
DEPENDS_append_class-native = " file-replacement-native bzip2-replacement-native"

# This matches the SWUPD_TOOLS_FORMAT in swupd-image.bbclass.
# When updating to a new release which changes the format of
# the output, copy the recipe first to ensure that the old
# release is still available if needed by swupd-image.bbclass,
# then bump this number.
#
# The rest of the recipe ensures that different swupd-server
# versions can be build and installed in parallel (format
# number embedded in PN and the resulting files).
SWUPD_SERVER_FORMAT = "4"
PN = "swupd-server-format${SWUPD_SERVER_FORMAT}"
FILESEXTRAPATHS_prepend = "${THISDIR}/swupd-server:"
PV = "3.6.3"
SRC_URI = "git://github.com/clearlinux/swupd-server.git;protocol=https \
           file://0001-Revert-Make-full-file-creation-for-directories-threa.patch \
           file://0029-fullfiles-use-libarchive-directly.patch \
           file://0003-swupd_create_pack-download-original-files-on-demand-.patch \
           file://0001-create_pack-rely-less-on-previous-builds.patch \
           file://0003-create_pack-abort-delta-handling-early-when-impossib.patch \
           file://0004-create_pack-download-via-libcurl-libarchive.patch \
           file://0002-pack.c-do-not-clean-packstage.patch \
           file://0001-type_change.c-allow-transition-dir-symlink.patch \
           "
SRCREV = "47addb4fa46a0ed38102bf7bb328f00cd29c3602"

S = "${WORKDIR}/git"

inherit pkgconfig autotools

EXTRA_OECONF = "--enable-bzip2 --enable-lzma --disable-stateless --disable-tests --enable-bsdtar"

# safer-calls-to-system-utilities.patch uses for loop initial declaration
CFLAGS_append = " -std=c99"

RDEPENDS_${PN} = "rsync"
RDEPENDS_${PN}_class-target = " bsdtar"

BBCLASSEXTEND = "native"

do_install_append () {
    for i in ${D}${bindir}/swupd_*; do
        mv $i ${i}_${SWUPD_SERVER_FORMAT}
    done
}
