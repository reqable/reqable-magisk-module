#!/system/bin/sh

exec > /data/local/tmp/CustomCACert.log
exec 2>&1
set -x

MODDIR=${0%/*}
CERT_DIR="${MODDIR}/system/etc/security/cacerts"
SYS_TARGET="/system/etc/security/cacerts"
APEX_TARGET="/apex/com.android.conscrypt/cacerts"

# 检查是否有 .0 证书文件，没有则直接退出，防止空挂载导致断网
if ! ls "${CERT_DIR}"/*.0 >/dev/null 2>&1; then
    echo "No .0 certificate found in ${CERT_DIR}, exiting."
    exit 0
fi

set_context() {
    [ "$(getenforce)" = "Enforcing" ] || return 0
    default_selinux_context=u:object_r:system_security_cacerts_file:s0
    selinux_context=$(ls -Zd "$1" | awk '{print $1}')

    if [ -n "$selinux_context" ] && [ "$selinux_context" != "?" ]; then
        chcon -R "$selinux_context" "$2"
    else
        chcon -R "$default_selinux_context" "$2"
    fi
}

TMP_DIR="/dev/reqable_cacerts"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
mount -t tmpfs tmpfs "${TMP_DIR}"

if [ -d "${APEX_TARGET}" ]; then
    cp -f "${APEX_TARGET}"/* "${TMP_DIR}/"
else
    cp -f "${SYS_TARGET}"/* "${TMP_DIR}/"
fi

# 仅复制 .0 结尾的合法证书文件，过滤掉 .gitkeep 或 ._ 隐藏垃圾文件
cp -f "${CERT_DIR}"/*.0 "${TMP_DIR}/"

chown -R 0:0 "${TMP_DIR}"
chmod 755 "${TMP_DIR}"
chmod 644 "${TMP_DIR}"/*
set_context "${SYS_TARGET}" "${TMP_DIR}"

mount --bind "${TMP_DIR}" "${SYS_TARGET}"
nsenter --mount=/proc/1/ns/mnt -- /bin/mount --bind "${TMP_DIR}" "${SYS_TARGET}" 2>/dev/null

if [ -d "${APEX_TARGET}" ]; then
    set_context "${APEX_TARGET}" "${TMP_DIR}"
    mount --bind "${TMP_DIR}" "${APEX_TARGET}"
    nsenter --mount=/proc/1/ns/mnt -- /bin/mount --bind "${TMP_DIR}" "${APEX_TARGET}" 2>/dev/null
fi

umount -l "${TMP_DIR}"
rmdir "${TMP_DIR}"