#!/system/bin/sh

exec > /data/local/tmp/CustomCACert.log
exec 2>&1

set -x

MODDIR=${0%/*}
CERT_DIR="${MODDIR}/system/etc/security/cacerts"

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

chown -R 0:0 "${CERT_DIR}"
set_context /system/etc/security/cacerts "${CERT_DIR}"

# Android 14+ APEX Conscrypt store
# Since Magisk ignores /apex for module file injections, use non-Magisk way
if [ -d /apex/com.android.conscrypt/cacerts ]; then
    apex_target=/apex/com.android.conscrypt/cacerts
    bind_dir="${MODDIR}/.bind_apex"

    rm -rf "${bind_dir}"
    mkdir -p "${bind_dir}"
    cp -f "${apex_target}"/* "${bind_dir}/"
    cp -f "${CERT_DIR}"/* "${bind_dir}/"
    chown -R 0:0 "${bind_dir}"
    set_context "${apex_target}" "${bind_dir}"

    mount --bind "${bind_dir}" "${apex_target}"
    mount -o remount,ro,bind "${apex_target}"
fi
