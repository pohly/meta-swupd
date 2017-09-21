# This version number *must* be a non-negative integer that fits in an int.
# It will be used as VERSION_ID in /usr/lib/os-release by images using
# swupd.
OS_VERSION ??= "${DISTRO_VERSION}"
python () {
    ver = d.getVar('OS_VERSION', True) or 'invalid'
    try:
        ver = int(ver)
    except ValueError:
        raise bb.parse.SkipRecipe("Invalid value for OS_VERSION (%s), must be a non-negative integer value." % ver)
    if ver <= 0 or ver > 2147483647:
        raise bb.parse.SkipRecipe('OS_VERSION outside of valid range (> 0, <= 2147483647): %d' % ver)
}

# Main directory in which swupd is invoked. The actual output which needs
# to be published will be in the "www" sub-directory. In addition, swupd-server
# uses it as the main work directory.
DEPLOY_DIR_SWUPD ??= "${DEPLOY_DIR}/swupd/${MACHINE}/${SWUPD_IMAGE_PN}"

# The information about where to find version information and actual
# content is needed in several places:
# - the swupd client in the image gets configured such that it uses that as default
# - swupd server needs information about the previous build
#
# The version URL determines what the client picks as the version that it updates to.
# The content URL must have all builds ever produced and is expected to also
# have the corresponding version information.
#
# The following two variables are used when configuring the swupd client.
SWUPD_VERSION_URL ??= "http://download.example.com/updates/my-distro/milestone/${MACHINE}/${SWUPD_IMAGE_PN}"
SWUPD_CONTENT_URL ??= "http://download.example.com/updates/my-distro/builds/${MACHINE}/${SWUPD_IMAGE_PN}"

# An absolute path for a file containing the SSL certificate that is
# is to be used for verifying https connections to the version and content
# server. Only used by the swupd client.
SWUPD_PINNED_PUBKEY ??= ""

# These two variables are used during the build process.
#
# When doing the initial build for a new update stream, remove DEPLOY_DIR_SWUPD
# (under TEMPDIR by default, so a build from scratch usually won't have it) without
# these variables set.
#
# For all following builds, either:
# - preserve the entire DEPLOY_DIR_SWUPD directory and leave the variables unset or
# - rsync the "www" directory under DEPLOY_DIR_SWUPD into a permanent location
#   and point to that with file:// or http(s):// URLs.
#
# The second approach uses less disk space and may be more efficient, depending on
# what data is needed from previous builds and how quickly they can be accessed. It
# is how meta-swupd is currently getting tested.
SWUPD_VERSION_BUILD_URL ??= ""
SWUPD_CONTENT_BUILD_URL ??= ""

# User configurable variables to disable all swupd processing or deltapack
# generation.
SWUPD_GENERATE ??= "1"

# By default, a new swupd update re-uses unchanged files from the
# previous build ("incremental update") and all changed files are
# stored in compressed tar archives (one per file). In this mode,
# swupd-client must download all modified files with multiple
# HTTP GET requests.
#
# To make updating more efficient, swupd can also prepare a single
# archive for updating from an older version to the current one
# ("delta update"). This archive then either contains modified files
# or even binary deltas (depending on what is smaller). Because
# generating deltas against all previous versions does not scale
# (build times and disk space would grow exponentially), the list of
# versions against which deltas are calculated must be chosen
# carefully.
#
# In a rolling release model where devices are expected to update to the
# latest version shortly after it gets published, generating deltas against
# some recent versions makes sense.
#
# In a release model based on milestone releases it might be better to
# generate deltas against those milestones.
#
# Because meta-swupd cannot make assumptions about which model is
# used, generating deltas is disabled by default. To enable it, set
# SWUPD_DELTAPACK_VERSIONS to a space-separated list of version
# numbers.
SWUPD_DELTAPACK_VERSIONS ??= ""

# Determines the verbosity of some messages about major steps in the
# update processing. "bbplain" makes them visible in the bitbake output.
SWUPD_LOG_FN ??= "bbdebug 1"

# We don't know exactly which formats will be in use during
# do_swupd_update. It depends on the content of the update
# repo, which is unavailable when dependencies are evaluated
# in preparation of the build.
#
# For now we simply build all supported server versions.
# If a distro knows that it has never used certain server
# versions, it can remove them (via SWUPD_SERVER_FORMATS_remove)
# or override the values directly.
SWUPD_SERVER_FORMATS ??= "3 4"

# When doing format changes, this version number is used for the intermediate
# release. Default is OS_VERSION - 1. There's a separate sanity check for
# OS_VERSION in the .inc file, so this code should always work.
OS_VERSION_INTERIM ??= "${@ ${OS_VERSION} - 1 }"

# The "format" needs to be bumped for different reasons:
# - the output of the swupd-server changes in a way that
#   a swupd-client currently installed on devices  will not
#   understand it (example: changing file names or using
#   a new compression method for archives)
# - the content of the distro changes such that a device
#   cannot update directly to the latest build (example:
#   the distro changes the boot loader and some swupd postinst
#   helper which knows about that change must be installed on
#   the device first before actually switching)
#
# meta-swupd handles the first case with SWUPD_TOOLS_FORMAT.
# The default value matches the default versions of the swupd-server
# and swupd-client. Distros can override this if they need to pick
# non-default versions of the tools, but that is not tested.
#
# Distros need to handle the second case by preparing and releasing
# a build that devices can update to (i.e. the version URL the devices
# check must have that update), then make the incompatible change and
# in the next build bump the SWUPD_DISTRO_FORMAT.
#
# In both cases, SWUPD_FORMAT gets bumped. meta-swupd notices that
# and then prepares a special transitional update:
# - the rootfs is configured to use the new SWUUPD_FORMAT and
#   OS_VERSION
# - a fake OS_VERSION-1 release is built using a swupd-server that is
#   compatible with the swupd-client before the bump
# - the OS_VERSION release then is the first one using the new format
#
# This way, devices are forced to update to OS_VERSION-1 because that
# will forever be the "latest" version for their current format.
# Once they have updated, the device really is on OS_VERSION, configured
# to use the new format, and the next update check will see future
# releases again.
#
# For this to work, "swupd-client" should always be invoked without
# explicit format parameter.
SWUPD_TOOLS_FORMAT ?= "4"
SWUPD_DISTRO_FORMAT ?= "0"
SWUPD_FORMAT = "${@ str(int('${SWUPD_TOOLS_FORMAT}') + int('${SWUPD_DISTRO_FORMAT}')) }"
