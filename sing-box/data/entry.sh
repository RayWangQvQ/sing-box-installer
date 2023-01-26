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
sing-box run -c $configFilePath
tail -f $logFilePath