#!/bin/bash
# Aegis Protocol: NUT Event Bridge
# Location: /usr/local/bin/upssched-cmd
# Triggered by /etc/nut/upssched.conf

case $1 in
    enter-siege)
        logger -t upssched-cmd "Executing Aegis Siege Mode..."
        /usr/local/bin/aegis-siege.sh
        ;;
    resume-siege)
        logger -t upssched-cmd "Executing Aegis Resume Mode..."
        /usr/local/bin/aegis-resume.sh
        ;;
    shutdown-now)
        logger -t upssched-cmd "Battery critical. Executing immediate host shutdown..."
        /sbin/shutdown -h +0 "UPS LOW BATTERY. AEGIS PROTOCOL INITIATING COLD SHUTDOWN."
        ;;
    *)
        logger -t upssched-cmd "Unrecognized command: $1"
        ;;
esac
