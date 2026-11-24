#!/bin/bash

set -e

MSGWARNING="\033[0;33mWARNING:\033[0m"

# setnumber falls back to the default when the variable isn't a whole number.
setnumber() {
    if ! [[ "${!1}" =~ ^[0-9]{1,9}$ ]]; then
        printf "%b Invalid %s given: %s (defaulting to %s)\\n" "$MSGWARNING" "$1" "${!1}" "$2"
        printf -v "$1" "%s" "$2"
    fi
    printf -v "$1" "%d" "$((10#${!1}))"
    printf "Setting %s to %s\\n" "$1" "${!1}"
}

setnumber BACKUPLIMIT 10
setnumber SERVERGAMEPORT 7777
setnumber SERVERMESSAGINGPORT 8888

# Engine.ini settings.
setnumber AUTOSAVENUM 5
setnumber MAXOBJECTS 2162688
setnumber MAXTICKRATE 30

[[ "${SERVERSTREAMING,,}" == "true" ]] && SERVERSTREAMING="1" || SERVERSTREAMING="0"
printf "Setting server streaming to %s\\n" "$SERVERSTREAMING"

setnumber TIMEOUT 30

# Game.ini settings.
setnumber MAXPLAYERS 4

ini_args=(
  "-ini:Engine:[/Script/FactoryGame.FGSaveSession]:mNumRotatingAutosaves=$AUTOSAVENUM"
  "-ini:Engine:[/Script/Engine.GarbageCollectionSettings]:gc.MaxObjectsInEditor=$MAXOBJECTS"
  "-ini:Engine:[/Script/OnlineSubsystemUtils.IpNetDriver]:LanServerMaxTickRate=$MAXTICKRATE"
  "-ini:Engine:[/Script/OnlineSubsystemUtils.IpNetDriver]:NetServerMaxTickRate=$MAXTICKRATE"
  "-ini:Engine:[/Script/OnlineSubsystemUtils.IpNetDriver]:ConnectionTimeout=$TIMEOUT"
  "-ini:Engine:[/Script/OnlineSubsystemUtils.IpNetDriver]:InitialConnectTimeout=$TIMEOUT"
  "-ini:Engine:[ConsoleVariables]:wp.Runtime.EnableServerStreaming=$SERVERSTREAMING"
  "-ini:Game:[/Script/Engine.GameSession]:ConnectionTimeout=$TIMEOUT"
  "-ini:Game:[/Script/Engine.GameSession]:InitialConnectTimeout=$TIMEOUT"
  "-ini:Game:[/Script/Engine.GameSession]:MaxPlayers=$MAXPLAYERS"
  "-ini:GameUserSettings:[/Script/Engine.GameSession]:MaxPlayers=$MAXPLAYERS"
)

# GameUserSettings.ini settings.
if [[ "${DISABLESEASONALEVENTS,,}" == "true" ]]; then
    printf "Disabling seasonal events\\n"
    ini_args+=("-DisableSeasonalEvents")
fi

# The server can't bind :: on hosts with IPv6 disabled in the kernel (#402).
if [[ "$MULTIHOME" == "::" ]] && { perl -MSocket -e 'socket(my $s, AF_INET6, SOCK_STREAM, 0) or exit 3'; [[ $? -eq 3 ]]; }; then
    printf "%b IPv6 is unavailable, so the server will only accept IPv4 connections\\n" "$MSGWARNING"
    MULTIHOME=""
fi

# Validate and set multihome address for network connections (useful for v6-only networks).
if [[ -n "$MULTIHOME" ]]; then
    if [[ "$MULTIHOME" != "::" ]]; then
        # IPv4 regex matches addresses from 0.0.0.0 to 255.255.255.255.
        IPv4='^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'

        # IPv6 regex supports full and shortened formats like 2001:db8::1.
        IPv6='^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:))$'

        if [[ "$MULTIHOME" =~ $IPv4 ]]; then
            printf "Multihome will accept IPv4 connections only\\n"
        elif [[ "$MULTIHOME" =~ $IPv6 ]]; then
            printf "Multihome will accept IPv6 connections only\\n"
        else
            printf "Invalid multihome address: %s (defaulting to ::)\\n" "$MULTIHOME"
            MULTIHOME="::"
        fi
    fi

    if [[ "$MULTIHOME" == "::" ]]; then
        printf "Multihome will accept IPv4 and IPv6 connections\\n"
    fi

    printf "Setting multihome to %s\\n" "$MULTIHOME"
    ini_args+=("-multihome=$MULTIHOME")
fi

if [[ "${SKIPUPDATE,,}" != "false" ]] && [ ! -f "/config/gamefiles/FactoryServer.sh" ]; then
    printf "%b Skip update is set, but no game files exist. Updating anyway\\n" "${MSGWARNING}"
    SKIPUPDATE="false"
fi

if [[ "${SKIPUPDATE,,}" != "true" ]]; then
    STEAMBETAPASSWORD=()

    if [[ -n "${STEAMBETAID}" ]]; then
        printf "STEAMBETAID is set. Using beta ID: %s\\n" "$STEAMBETAID"
        STEAMBETAFLAG="$STEAMBETAID"
        if [[ -n "${STEAMBETAKEY}" ]]; then
            STEAMBETAPASSWORD=(-betapassword "$STEAMBETAKEY")
            printf "Beta password provided\\n"
        fi
    elif [[ "${STEAMBETA,,}" == "true" ]]; then
        printf "Experimental flag is set. Experimental will be downloaded instead of the public release.\\n"
        STEAMBETAFLAG="experimental"
    else
        STEAMBETAFLAG="public"
    fi

    STORAGEAVAILABLE=$(stat -f -c "%a*%S" .)
    STORAGEAVAILABLE=$((STORAGEAVAILABLE/1024/1024/1024))
    printf "Checking available storage: %sGB detected\\n" "$STORAGEAVAILABLE"

    if [[ "$STORAGEAVAILABLE" -lt 8 ]]; then
        printf "You have less than 8GB (%sGB detected) of available storage to download the game.\\nIf this is a fresh install, it will probably fail.\\n" "$STORAGEAVAILABLE"
    fi

    printf "\\nDownloading the latest version of the game...\\n"
    if [ -f "/config/gamefiles/steamapps/appmanifest_${STEAMAPPID}.acf" ]; then
        printf "\\nRemoving the app manifest to force Steam to check for an update...\\n"
        rm "/config/gamefiles/steamapps/appmanifest_${STEAMAPPID}.acf" || true
    fi
    if ! steamcmd +force_install_dir /config/gamefiles +login anonymous +app_update "$STEAMAPPID" -beta "$STEAMBETAFLAG" "${STEAMBETAPASSWORD[@]}" validate +quit; then
        # steamcmd recreates the manifest once it starts changing files, and StateFlags 4 means fully installed.
        if [ -f "/config/gamefiles/steamapps/appmanifest_${STEAMAPPID}.acf" ] && ! grep -qE '"StateFlags"\s+"4"' "/config/gamefiles/steamapps/appmanifest_${STEAMAPPID}.acf"; then
            printf "Game update failed partway through. Not launching a partially updated game.\\n"
            exit 1
        fi
        printf "%b Game update failed, launching the installed version\\n" "${MSGWARNING}"
    fi
    cp -r /home/steam/.steam/steam/logs/* "/config/logs/steam" || printf "Failed to store Steam logs\\n"
else
    printf "Skipping update as flag is set\\n"
fi

printf "Launching game server\\n\\n"

# Skip unchanged saves so a crash loop can't rotate out good backups.
latestbackup=$(find /config/backups -mindepth 1 -maxdepth 1 -type d -name '????-??-??_??-??-??' | sort -r | head -n 1)
if [[ "$BACKUPLIMIT" -gt 0 ]] && [ -n "$(ls -A /config/saved/server)" ] && { [ -z "$latestbackup" ] || ! diff -rq /config/saved/server "$latestbackup" >/dev/null; }; then
    backupdir="/config/backups/$(date -u +%Y-%m-%d_%H-%M-%S)"
    mkdir -p "$backupdir"
    cp -r "/config/saved/server/." "$backupdir"
fi
if [[ "$BACKUPLIMIT" -gt 0 ]]; then
    find /config/backups -mindepth 1 -maxdepth 1 -type d -name '????-??-??_??-??-??' | sort -r | tail -n +"$((BACKUPLIMIT + 1))" | xargs -r rm -rf
fi
rm -rf "$GAMESAVESDIR"
ln -sf "/config/saved" "$GAMESAVESDIR"

if [ ! -f "/config/gamefiles/FactoryServer.sh" ]; then
    printf "FactoryServer launch script is missing.\\n"
    exit 1
fi

cd /config/gamefiles || exit 1

chmod +x FactoryServer.sh || true
./FactoryServer.sh -Port="$SERVERGAMEPORT" -ReliablePort="$SERVERMESSAGINGPORT" -ExternalReliablePort="$SERVERMESSAGINGPORT" "${ini_args[@]}" "$@" &
server_pid=$!

# api sends stdin as the request data, keeping secrets out of process args.
api() {
    local header="" host="127.0.0.1"
    if [[ -n "$MULTIHOME" && "$MULTIHOME" != "::" ]]; then
        host="$MULTIHOME"
        [[ "$host" == *:* ]] && host="[$host]"
    fi

    # The API rejects an empty bearer header as malformed.
    if [[ -n "${2:-}" ]]; then
        header="Authorization: Bearer $2"
    fi

    jq -c --arg function "$1" '{function: $function, data: .}' \
        | curl -k -s -S --max-time 10 -X POST "https://${host}:${SERVERGAMEPORT}/api/v1" \
            -H "Content-Type: application/json" -H @/dev/fd/3 -d @- 3<<< "$header"
}

# apierror prints the API error message, or the raw response when it isn't JSON.
apierror() {
    [[ -n "$1" ]] || { echo "no response"; return; }
    jq -r '.errorMessage // .' <<< "$1" 2>/dev/null || echo "$1"
}

# claimserver only succeeds once: claimed servers refuse passwordless login.
claimserver() {
    local response token
    # Runs in the background, so a failed call must reach the warnings below instead of silently exiting.
    set +e

    until bash /home/steam/healthcheck.sh >/dev/null 2>&1; do
        kill -0 "$server_pid" 2>/dev/null || return 0
        sleep 10
    done

    response=$(echo '{"MinimumPrivilegeLevel":"InitialAdmin"}' | api PasswordlessLogin)
    token=$(jq -r '.data.authenticationToken // empty' <<< "$response" 2>/dev/null)
    if [[ "$(jq -r '.errorCode // empty' <<< "$response" 2>/dev/null)" == "passwordless_login_not_possible" ]]; then
        printf "Server is already claimed, ignoring SERVERADMINPASSWORD, SERVERNAME and SERVERPASSWORD\\n"
        return 0
    elif [[ -z "$token" ]]; then
        printf "%b Failed to log in to claim the server: %s\\n" "$MSGWARNING" "$(apierror "$response")"
        return 0
    fi

    response=$(jq -n '{ServerName: env.SERVERNAME, AdminPassword: env.SERVERADMINPASSWORD}' | api ClaimServer "$token")
    token=$(jq -r '.data.authenticationToken // empty' <<< "$response" 2>/dev/null)
    if [[ -z "$token" ]]; then
        printf "%b Failed to claim the server: %s\\n" "$MSGWARNING" "$(apierror "$response")"
        return 0
    fi
    printf "Claimed the server as %s\\n" "$SERVERNAME"

    if [[ -n "$SERVERPASSWORD" ]]; then
        # Success is an empty response, so a failed request must not count as one.
        if ! response=$(jq -n '{Password: env.SERVERPASSWORD}' | api SetClientPassword "$token") || [[ -n "$response" ]]; then
            printf "%b Failed to set the server password, set it in-game: %s\\n" "$MSGWARNING" "$(apierror "$response")"
            return 0
        fi
        printf "Set the server password\\n"
    fi
}

if [[ -n "$SERVERADMINPASSWORD" ]]; then
    claimserver &
fi

# Background jobs ignore SIGINT, so signal the game (FactoryServer.sh's child) directly.
shutdown() {
    printf "\\nReceived shutdown signal. Shutting down.\\n"
    pkill -INT -P "$server_pid" || true
    kill -INT "$server_pid" 2>/dev/null || true
}
trap shutdown SIGINT SIGTERM

# wait returns when the trap fires; keep waiting or PID 1 exits and the game is killed.
while kill -0 "$server_pid" 2>/dev/null; do
    wait "$server_pid" || true
done
wait "$server_pid"
