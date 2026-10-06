#!/bin/bash
# Run a command on the Knulli test device (see memory/knulli-ssh-access): knulli.sh '<cmd>'
exec sshpass -f "$HOME/.ssh/knulli.pass" ssh -o StrictHostKeyChecking=accept-new root@${KNULLI_HOST:?set KNULLI_HOST to the device address} "$@"
