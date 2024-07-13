#!/bin/bash
###
 # @Author: Ray zai7lou@outlook.com
 # @Date: 2024-07-12 22:00:19
 # @LastEditors: Ray zai7lou@outlook.com
 # @LastEditTime: 2024-07-13 10:22:23
 # @FilePath: \sing-box-installer\sing-box\data\entry.sh
 # @Description: 
 # 
 # Copyright (c) 2024 by ${git_name_email}, All Rights Reserved. 
### 
set -e

dir_data=$1
nohup=$2

configFilePath="$dir_data/config.json"
logFilePath="$dir_data/sing-box.log"

echo "entry"
sing-box version

# https://sing-box.sagernet.org/configuration/
echo -e "\nconfig:"
sing-box check -c $configFilePath || cat $configFilePath
sing-box format -c $configFilePath -w
cat $configFilePath

echo -e "\nstarting"
touch $logFilePath

if [ $nohup == "true" ]; then
    echo "running with nohup"
    nohup sing-box run -c $configFilePath &
    sleep 5s
    cat $logFilePath
else
    sing-box run -c $configFilePath 2>&1 | tee -a $logFilePath
fi
