#!/bin/bash

set -e

printf "===== Satisfactory Server %s =====\\nhttps://github.com/robtme/satisfactory-server\\n\\n" "$VERSION"

MSGERROR="\033[0;31mERROR:\033[0m"
MSGWARNING="\033[0;33mWARNING:\033[0m"
NUMCHECK='^[0-9]+$'
CPUMODEL=$(lscpu | grep '^Model name:' | sed 's/Model name:[[:space:]]*//g')
RAMAVAILABLE=$(awk '/MemAvailable/ {printf( "%d\n", $2 / 1048576 )}' /proc/meminfo)

# Container memory limits only show up in the cgroup (v2, then v1).
RAMLIMIT=$(cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null | head -n 1)
if [[ "$RAMLIMIT" =~ $NUMCHECK ]] && [[ $(( RAMLIMIT / 1073741824 )) -lt "$RAMAVAILABLE" ]]; then
    RAMAVAILABLE=$(( RAMLIMIT / 1073741824 ))
fi

export CURRENTGID=$(id -g)
export CURRENTUID=$(id -u)
export HOME="/home/steam"
export STEAMGID=$(id -g steam)
export STEAMUID=$(id -u steam)
export USER="steam"

if [[ "${DEBUG,,}" == "true" ]]; then
    printf "Debugging enabled (the container will exit after printing the debug info)\\n\\nPrinting environment variables:\\n"
    # Users paste this output into public issues.
    export | sed -E 's/((STEAMBETAKEY|SERVERADMINPASSWORD|SERVERPASSWORD)=).*/\1"<redacted>"/'

    echo "
System info:
OS:  $(uname -a)
CPU: ${CPUMODEL}
RAM: ${RAMAVAILABLE}GB available ($(awk '/MemTotal/ {printf( "%d\n", $2 / 1048576 )}' /proc/meminfo)GB host total)
HDD: $(df -h | awk '$NF=="/"{printf "%dGB/%dGB (%s used)\n", $3,$2,$5}')"
    printf "\\nCurrent version:\\n%s" "${VERSION}"
    printf "\\nCurrent user:\\n%s" "$(id)"
    printf "\\nProposed user:\\nuid=%s(?) gid=%s(?) groups=%s(?)\\n" "$PUID" "$PGID" "$PGID"
    printf "\\nExiting...\\n"
    exit 1
fi

# check that the cpu isn't generic, as Satisfactory will normally crash
if [[ "${VMOVERRIDE,,}" == "true" ]]; then
    printf "${MSGWARNING} VMOVERRIDE is enabled, skipping CPU model check. Satisfactory might crash!\\n"
else
    if [[ "$CPUMODEL" == "Common KVM processor" || "$CPUMODEL" == *"QEMU"* ]]; then
        printf "${MSGERROR} Your CPU model is configured as \"${CPUMODEL}\", which will cause Satisfactory to crash.\\nIf you have control over your hypervisor (ESXi, Proxmox, etc.), you should be able to easily change this.\\nOtherwise contact your host/administrator for assistance.\\n"
        exit 1
    fi
fi

printf "Checking available memory: %sGB detected\\n" "$RAMAVAILABLE"
if [[ "$RAMAVAILABLE" -lt 8 ]]; then
    printf "${MSGWARNING} You have less than the required 8GB minimum (%sGB detected) of available RAM to run the game server.\\nThe server will likely run fine, though may run into issues in the late game (or with 4+ players).\\n" "$RAMAVAILABLE"
fi

# prevent large logs from accumulating by default
if [[ "${LOG,,}" != "true" ]]; then
    printf "Clearing old Satisfactory logs (set LOG=true to disable this)\\n"
    find "${GAMECONFIGDIR}/Logs" -mindepth 1 -delete 2>/dev/null || true
fi

if [[ "$CURRENTUID" -ne "0" ]]; then
    if [[ "$STEAMUID" -ne "$CURRENTUID" ]] || [[ "$STEAMGID" -ne "$CURRENTGID" ]]; then
        printf "${MSGERROR} Current user (%s:%s) is not root (0:0), and doesn't match the steam user/group (%s:%s).\\nTo run the container as non-root with a UID/GID that differs from the steam user, you must build the Docker image with the UID and GID build arguments set.\\n" "$CURRENTUID" "$CURRENTGID" "$STEAMUID" "$STEAMGID"
        exit 1
    fi

    printf "${MSGWARNING} Running as non-root user (%s:%s).\\n" "$CURRENTUID" "$CURRENTGID"
fi

if ! [[ "$PGID" =~ $NUMCHECK ]] ; then
    printf "${MSGWARNING} Invalid group id given: %s\\n" "$PGID"
    PGID="1000"
elif [[ "$PGID" -eq 0 ]]; then
    printf "${MSGERROR} PGID/group cannot be 0 (root)\\n"
    exit 1
fi

if ! [[ "$PUID" =~ $NUMCHECK ]] ; then
    printf "${MSGWARNING} Invalid user id given: %s\\n" "$PUID"
    PUID="1000"
elif [[ "$PUID" -eq 0 ]]; then
    printf "${MSGERROR} PUID/user cannot be 0 (root)\\n"
    exit 1
fi

if [[ "$CURRENTUID" -eq "0" ]]; then
    if [[ $(getent group "$PGID" | cut -d: -f1) ]]; then
        usermod -a -G "$PGID" steam
    else
        groupmod -g "$PGID" steam
    fi

    if [[ $(getent passwd "$PUID" | cut -d: -f1) ]]; then
        USER=$(getent passwd "$PUID" | cut -d: -f1)
    else
        usermod -u "$PUID" steam
    fi
fi

if [[ ! -w "/config" ]]; then
    echo "The current user does not have write permissions for /config"
    exit 1
fi

mkdir -p \
    /config/backups \
    /config/gamefiles \
    /config/logs/steam \
    /config/saved/blueprints \
    /config/saved/server \
    "${GAMECONFIGDIR}/Config/LinuxServer" \
    "${GAMECONFIGDIR}/Logs" \
    "${GAMESAVESDIR}/server" \
    /home/steam/.steam/root \
    /home/steam/.steam/steam \
    || exit 1

echo "Satisfactory logs can be found in ${GAMECONFIGDIR}/Logs" > /config/logs/satisfactory-path.txt

if [[ "$CURRENTUID" -eq "0" ]]; then
    # chown -R over the whole game install is slow on every start.
    find /config /home/steam /tmp/dumps \( ! -user "$PUID" -o ! -group "$PGID" \) -exec chown -h "$PUID":"$PGID" {} +
    # Without a group, gosu uses the user's primary group instead of PGID.
    exec gosu "$USER:$PGID" "/home/steam/run.sh" "$@"
else
    # running within a rootless environment
    exec "/home/steam/run.sh" "$@"
fi
