SUMMARY = "swupd sofware update from Clear Linux - client component"
HOMEPAGE = "https://github.com/clearlinux/swupd-client"
LICENSE = "GPL-2.0"
LIC_FILES_CHKSUM = "file://COPYING;md5=f8d90fb802930e30e49c39c8126a959e"

DEPENDS = "glib-2.0 curl openssl libarchive bsdiff"

PV = "3.12.0"
SRC_URI = "git://github.com/clearlinux/swupd-client.git;protocol=https \
           file://swupd-update-partition.sh \
           file://0001-swupd-show-tar-errors.patch \
           file://0002-downloads-support-mixing-http-and-file-URLs.patch \
           "
SRCREV = "89a47cde78331e4a2b1958da847670e3cfa55fae"

S = "${WORKDIR}/git"

RDEPENDS_${PN}_append_class-target = " oe-swupd-helpers bsdtar"
# We check /etc/os-release for the current OS version number
RRECOMMENDS_${PN}_class-target = "os-release"

# The current format is determined by the source code of the
# swupd-client that is in the image.
#
# Watch the release notes and/or source code of the client carefully
# and bump the number by one for each update of the recipe where we
# switch to a source that has a format change.
#
# To switch to a client with a new format also update SWUPD_TOOLS_FORMAT in
# swupd-image.bbclass.
SWUPD_CLIENT_FORMAT = "4"
RPROVIDES_${PN} = "swupd-client-format${SWUPD_CLIENT_FORMAT}"

inherit pkgconfig autotools systemd distro_features_check

REQUIRED_DISTRO_FEATURES_class-target = "systemd"

EXTRA_OECONF = "\
    --with-systemdsystemunitdir=${systemd_system_unitdir} \
    --enable-bsdtar \
    --disable-tests \
    --enable-xattr \
"

PACKAGECONFIG ??= "stateless"
PACKAGECONFIG[stateless] = ",--disable-stateless"

do_patch[postfuncs] += "fix_paths "
fix_paths () {
    # /usr/bin/systemctl is currently hard-coded in src/scripts.c update_triggers(),
    # which may or may not be the right path.
    sed -i -e 's;/usr/bin/systemctl;${bindir}/systemctl;g' ${S}/src/*
}

do_install_append() {
    install ${WORKDIR}/swupd-update-partition.sh ${D}${bindir}/swupd-update-partition
}

PACKAGES =+ " \
    ${PN}-verifytime \
    ${PN}-verifytime-service \
    ${PN}-update-service \
    ${PN}-check-service \
"

# swupd_init() invokes verifytime.
RDEPENDS_${PN}_class-target = "${PN}-verifytime"

FILES_${PN}-verifytime = " \
    ${bindir}/verifytime \
"

FILES_${PN}-verifytime-service = " \
    ${systemd_system_unitdir}/verifytime.service \
"
RDEPENDS_${PN}-update-service = "${PN}-verifytime"
SYSTEMD_SERVICE_${PN}-verifytime-service = "verifytime.service"
SYSTEMD_AUTO_ENABLE_${PN}-verifytime-service = "enable"

FILES_${PN}-update-service = " \
    ${systemd_system_unitdir}/swupd-update.* \
"
RDEPENDS_${PN}-update-service = "${PN}"
SYSTEMD_SERVICE_${PN}-update-service = "swupd-update.timer swupd-update.service"
SYSTEMD_AUTO_ENABLE_${PN}-update-service = "enable"

FILES_${PN}-check-service = " \
    ${systemd_system_unitdir}/check-update.* \
"
RDEPENDS_${PN}-check-service = "${PN}"
SYSTEMD_SERVICE_${PN}-check-service = "check-update.timer check-update.service"
SYSTEMD_AUTO_ENABLE_${PN}-check-service = "enable"

BBCLASSEXTEND = "native"
