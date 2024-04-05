#!/bin/bash
set -e

configFilePath="/data/config.json"
logFilePath="/data/sing-box.log"

echo "entry"
sing-box version

# https://sing-box.sagernet.org/configuration/
echo -e "\nconfig:"
sing-box check -c $configFilePath || cat $configFilePath
sing-box format -c /data/config.json -w
cat $configFilePath

echo -e "\nstarting"
touch $logFilePath
sing-box run -c $configFilePath 2>&1 | tee -a $logFilePath
