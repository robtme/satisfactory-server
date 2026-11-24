FROM steamcmd/steamcmd:ubuntu-22

ARG DEBIAN_FRONTEND="noninteractive"
ARG GID=1000
ARG UID=1000

ENV AUTOSAVENUM="5" \
    BACKUPLIMIT="10" \
    DEBUG="false" \
    DISABLESEASONALEVENTS="false" \
    GAMECONFIGDIR="/config/gamefiles/FactoryGame/Saved" \
    GAMESAVESDIR="/home/steam/.config/Epic/FactoryGame/Saved/SaveGames" \
    LOG="false" \
    MAXOBJECTS="2162688" \
    MAXPLAYERS="4" \
    MAXTICKRATE="30" \
    MULTIHOME="::" \
    PGID="1000" \
    PUID="1000" \
    SERVERGAMEPORT="7777" \
    SERVERMESSAGINGPORT="8888" \
    SERVERNAME="Satisfactory Server" \
    SERVERSTREAMING="true" \
    SKIPUPDATE="false" \
    STEAMAPPID="1690800" \
    STEAMBETA="false" \
    STEAMBETAID="" \
    STEAMBETAKEY="" \
    TIMEOUT="30" \
    VMOVERRIDE="false"

# hadolint ignore=DL3008
RUN set -x \
 && apt-get update \
 && apt-get install -y gosu xdg-user-dirs curl jq tzdata --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -g ${GID} steam \
 && useradd -l -u ${UID} -g ${GID} -ms /bin/bash steam \
 && mkdir -p /config /home/steam/.local/share/Steam/ \
 && cp -R /root/.local/share/Steam/steamcmd/ /home/steam/.local/share/Steam/steamcmd/ \
 && chown -R ${UID}:${GID} /config /home/steam/.local/ \
 && gosu nobody true

COPY --chmod=755 init.sh /
COPY --chown=steam:steam --chmod=755 healthcheck.sh run.sh /home/steam/

HEALTHCHECK --timeout=30s --start-period=300s CMD ["bash", "/home/steam/healthcheck.sh"]

WORKDIR /config
ARG VERSION="DEV"
ENV VERSION=$VERSION
LABEL version=$VERSION
STOPSIGNAL SIGINT
EXPOSE 7777/udp 7777/tcp 8888/tcp

ENTRYPOINT [ "/init.sh" ]