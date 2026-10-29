#!/system/bin/sh

exec >> /data/local/tmp/CustomCACert.log 2>&1
set -x

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

MODDIR=${0%/*}
CERT_DIR="${MODDIR}/system/etc/security/cacerts"
SYS_TARGET="/system/etc/security/cacerts"
APEX_TARGET="/apex/com.android.conscrypt/cacerts"

# 精准获取第一个 .0 证书的文件名（如 b5c7838e.0）
CERT_PATH=$(ls "${CERT_DIR}"/*.0 2>/dev/null | head -n 1)
[ -z "${CERT_PATH}" ] && exit 0
CERT_FILE=$(basename "${CERT_PATH}")

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

inject_certs() {
    TMP_DIR="/dev/reqable_late"
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    mount -t tmpfs tmpfs "${TMP_DIR}"

    if [ -d "${APEX_TARGET}" ]; then
        cp -f "${APEX_TARGET}"/* "${TMP_DIR}/"
    else
        cp -f "${SYS_TARGET}"/* "${TMP_DIR}/"
    fi
    cp -f "${CERT_DIR}"/*.0 "${TMP_DIR}/"

    chown -R 0:0 "${TMP_DIR}"
    chmod 755 "${TMP_DIR}"
    chmod 644 "${TMP_DIR}"/*
    set_context "${SYS_TARGET}" "${TMP_DIR}"

    if [ ! -f "${SYS_TARGET}/${CERT_FILE}" ]; then
        mount --bind "${TMP_DIR}" "${SYS_TARGET}"
    fi

    if [ -d "${APEX_TARGET}" ]; then
        set_context "${APEX_TARGET}" "${TMP_DIR}"
        if [ ! -f "${APEX_TARGET}/${CERT_FILE}" ]; then
            mount --bind "${TMP_DIR}" "${APEX_TARGET}"
        fi
    fi

    for pid in $(pidof zygote zygote64); do
        if ! nsenter --mount=/proc/$pid/ns/mnt -- ls "${SYS_TARGET}/${CERT_FILE}" >/dev/null 2>&1; then
            nsenter --mount=/proc/$pid/ns/mnt -- /bin/mount --bind "${TMP_DIR}" "${SYS_TARGET}"
        fi
        if [ -d "${APEX_TARGET}" ]; then
            if ! nsenter --mount=/proc/$pid/ns/mnt -- ls "${APEX_TARGET}/${CERT_FILE}" >/dev/null 2>&1; then
                nsenter --mount=/proc/$pid/ns/mnt -- /bin/mount --bind "${TMP_DIR}" "${APEX_TARGET}"
            fi
        fi
    done

    umount -l "${TMP_DIR}"
    rmdir "${TMP_DIR}"
}

NEED_INJECT=0
[ ! -f "${SYS_TARGET}/${CERT_FILE}" ] && NEED_INJECT=1
[ -d "${APEX_TARGET}" ] && [ ! -f "${APEX_TARGET}/${CERT_FILE}" ] && NEED_INJECT=1

for pid in $(pidof zygote zygote64); do
    if [ -d "${APEX_TARGET}" ]; then
        nsenter --mount=/proc/$pid/ns/mnt -- ls "${APEX_TARGET}/${CERT_FILE}" >/dev/null 2>&1 || NEED_INJECT=1
    else
        nsenter --mount=/proc/$pid/ns/mnt -- ls "${SYS_TARGET}/${CERT_FILE}" >/dev/null 2>&1 || NEED_INJECT=1
    fi
done

if [ "$NEED_INJECT" = "1" ]; then
    inject_certs
fi