#!/system/bin/sh

exec > /data/local/tmp/CustomCACert.log
exec 2>&1

set -x

MODDIR=${0%/*}

set_context() {
    [ "$(getenforce)" = "Enforcing" ] || return 0

    default_selinux_context=u:object_r:system_file:s0
    selinux_context=$(ls -Zd $1 | awk '{print $1}')

    if [ -n "$selinux_context" ] && [ "$selinux_context" != "?" ]; then
        chcon -R $selinux_context $2
    else
        chcon -R $default_selinux_context $2
    fi
}

merge_ca_certs() {
    target_path="$1"
    tmpfs_path="$2"

    rm -f "${tmpfs_path}"
    mkdir -p "${tmpfs_path}"
    mount -t tmpfs tmpfs "${tmpfs_path}"
    cp -f "${target_path}"/* "${tmpfs_path}/"

    cp -f ${MODDIR}/system/etc/security/cacerts/* "${tmpfs_path}"
    chown -R 0:0 "${tmpfs_path}"
    set_context "${target_path}" "${tmpfs_path}"

    CERTS_NUM="$(ls -1 "${tmpfs_path}" | wc -l)"
    if [ "$CERTS_NUM" -gt 10 ]; then
        mount --bind "${tmpfs_path}" "${target_path}"
        for pid in 1 $(pgrep zygote) $(pgrep zygote64); do
            nsenter --mount=/proc/${pid}/ns/mnt -- \
                mount --bind "${tmpfs_path}" "${target_path}"
        done
    else
        echo "Cancelling replacing ${target_path} due to safety"
    fi
    for pid in 1 $(pgrep zygote) $(pgrep zygote64); do
        nsenter --mount=/proc/${pid}/ns/mnt -- \
            umount "${tmpfs_path}"
    done
    umount "${tmpfs_path}"
    rmdir "${tmpfs_path}"
}

chown -R 0:0 ${MODDIR}/system/etc/security/cacerts
set_context /system/etc/security/cacerts ${MODDIR}/system/etc/security/cacerts

# Android 14+ APEX Conscrypt store
# Since Magisk ignores /apex for module file injections, use non-Magisk way
if [ -d /apex/com.android.conscrypt/cacerts ]; then
    merge_ca_certs /apex/com.android.conscrypt/cacerts /data/local/tmp/sys-ca-copy
fi

# System CA store (for Flutter/dart:io HttpClient and other legacy clients)
if [ -d /system/etc/security/cacerts ]; then
    merge_ca_certs /system/etc/security/cacerts /data/local/tmp/sys-ca-copy-system
fi
