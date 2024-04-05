#!/bin/bash
set -e

configFilePath="/data/config.json"
logFilePath="/data/sing-box.json"

echo "entry"
sing-box version

# https://sing-box.sagernet.org/configuration/
echo -e "\nconfig:"
sing-box check -c $configFilePath || cat $configFilePath
sing-box format -c /data/config.json -w
cat $configFilePath

echo -e "\nstarting"
touch $logFilePath
tail -f $logFilePath &
sing-box run -c $configFilePath
