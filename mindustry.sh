#!/bin/bash
for i in {0..9}; do
    test -S $XDG_RUNTIME_DIR/discord-ipc-$i || ln -sf {app/com.discordapp.Discord,$XDG_RUNTIME_DIR}/discord-ipc-$i;
    test -S $XDG_RUNTIME_DIR/discord-ipc-$i || ln -sf {app/com.discordapp.DiscordCanary,$XDG_RUNTIME_DIR}/discord-ipc-$i;
done

java -jar /app/bin/Mindustry.jar  $@
