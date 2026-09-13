# -*- mode: sh -*-
# Atlantic's WPE plugin and helpers live outside the default jail. Without
# these noblacklists, org.wpewebkit.qtwpe fails to load (libjpeg.so.8 lives
# in wpe-compat) and the dashboard stays on "Preparing session...".
# LD_LIBRARY_PATH must be set here: ld.so reads it at exec, so qputenv in
# the app is too late for libqtwpe.so's DT_NEEDED.

noblacklist /opt/wpe-sfos
noblacklist /usr/libexec/wpe-webkit-2.0
noblacklist /usr/lib64/wpe-compat
noblacklist /usr/lib/wpe-compat
noblacklist /dev/kgsl-3d0
noblacklist /dev/ion
noblacklist /dev/dri

mkdir     ${HOME}/.cache/wpe
whitelist ${HOME}/.cache/wpe

# Daily diagnostics for lockups and connection faults.
mkdir     ${HOME}/Documents/Helmsman
whitelist ${HOME}/Documents/Helmsman

env LD_LIBRARY_PATH=/usr/lib64/wpe-compat:/usr/lib/wpe-compat:/usr/lib64:/usr/lib:/opt/wpe-sfos/lib
env WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
