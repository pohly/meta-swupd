# Recipe created by recipetool
# This is the basis of a recipe and may need further editing in order to be fully functional.
# (Feel free to remove these comments when editing.)

# WARNING: the following LICENSE and LIC_FILES_CHKSUM values are best guesses - it is
# your responsibility to verify that the values are complete and correct.
#
# The following license files were not able to be identified and are
# represented as "Unknown" below, you will need to check them yourself:
#   COPYING
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/COPYING;md5=2ee41112a44fe7014dce33e26468ba93"

GO_IMPORT = "github.com/matthewrsj/mixer-tools/"
SRC_URI = " \
    git://${GO_IMPORT} \
"

DEPENDS = "golang-x-sys"

# Modify these as desired
PV = "1.0+git${SRCPV}"
SRCREV = "${AUTOREV}"
SRCREV_sys = "9167dbfd0f8e88b731dd88cbf73a270701a37bb4"

inherit go

# The mixer-tools use plain "import helpers" without path, so we have
# to extend GOPATH to avoid "cannot find package "helpers" in any
# of..."  errors.
GOPATH .= ":${B}/src/${GO_IMPORT}"

do_install_append () {
    install -d ${D}${bindir}
    install -m 755 ${S}/src/${GO_IMPORT}pack-maker.sh ${D}${bindir}/mixer-pack-maker.sh
}

# mixer depends at runtime on tools like swupd-server. The recipe
# itself does not try to hide that behind RDEPENDS, because callers
# like swupd-image.bbclass will have to do extra work anyway to handle
# format changes.

BBCLASSEXTEND = "native nativesdk"
