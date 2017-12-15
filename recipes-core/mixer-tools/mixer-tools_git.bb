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

unpack_additional () {
    for i in builder helpers; do
        ln -fs ${S}/src/$i ${GOPATH}/src/$i
    done
}
do_unpack[postfuncs] += "unpack_additional"

BBCLASSEXTEND = "native nativesdk"
