
# ---- cubecos tail (core/fixpacks/install.sh), appended to every fixpack's install.sh ----
# 3.2.0+: fixpacks install per node; hex_fixpack_install and fixpack_sync handle this node.
#
# Stage every file this fixpack wrote, so fixpack_sync's git_push records it. git_push
# commits what is staged, but stages only files git already tracks (git add -u): a file the
# image never had, such as new firmware or a new module, would be left out of the node's
# record. Ignored paths (/boot, /etc, /var, ...) are skipped; git does not record them anyway.
# This must never fail the install: the files are already in place, and install.sh's exit
# status is the install's result.
if [ -e $FIXPACK_MNT/rootfs.cgz ] && git -C / rev-parse --git-dir >/dev/null 2>&1 ; then
    zcat $FIXPACK_MNT/rootfs.cgz | cpio -it --quiet 2>/dev/null | sed 's|^\./||' |
        while read -r f ; do [ -f "/$f" ] || [ -L "/$f" ] && echo "$f" ; done |
        git -C / check-ignore --stdin -v -n --no-index 2>/dev/null | awk -F'\t' '$1 == "::" {print $2}' |
        git -C / add --pathspec-from-file=- 2>&1 || echo "Warning: could not stage this fixpack's files for its git record"
fi
true
