#!/bin/sh

# include the Onion sh lib
. /usr/lib/onion/lib.sh

# include wifisetup lib
. /usr/bin/wifisetup -noop

# function to return an array of all apps and if the app has an icon there
# 	argument 1: directory to check
AppList () {
	bExists=0

	# json setup           
	json_init              
	
	# create the directory array
	json_add_array apps
	
	#check if the directory exists
	if [ -d $1 ]
	then
		# denote that the directory exists
		bExists=1

		# go to the directory
		cd $1
		
		# grab all the app.json files and correct the formatting                          
		appList=`find . -name "app.json" | tr '\n' ';'`
		
		# split the list of json files
		rest=$appList
		while [ "$rest" != "" ]
		do
			val=${rest%%;*}
			rest=${rest#*;}

			# read in the contents of the json file
			appData=`cat $val | tr '\n' ' '`
			
			# find json commands to run for the app json file
			jshnCmd=`jshn -r "$appData"`
			# remove the json_init call
			jshnCmd=`echo $jshnCmd | sed -e 's/json_init;//'`

			# create and populate object for this app
			json_add_object 
			eval $jshnCmd
			json_close_object
		done	
	fi

	# finish the array
	json_close_array
	
	# add the note that the directory exists
	json_add_boolean exists $bExists

	# print the json
	json_dump
}

# function to control shellinabox daemon
ShellinaboxCtrl () {
	# parse the arguments object
	local argumentString=$(_ParseArgumentsObject)

	# initialize json response object
	json_init

	# check arguments for supported commands
	for argument in $argumentString
	do
		if [ "$argument" == "-start" ]
		then
			# start the shellinabox daemon (if there are none running)
			Log "ShellinaboxCtrl:: Start the shellinabox daemon, current count is $count"

			/etc/init.d/shellinabox start
			json_add_boolean "start" 1
		elif [ "$argument" == "-check" ]
		then
			# check if the shellinabox daemon is running
			Log "ShellinaboxCtrl:: Check for shellinabox daemon"
			Log "ShellinaboxCtrl:: found following pids: $pids"

			# find the pids of any running shellinabox processes
			pids=$(_getPids shellinabox ubus)

			# count the number of processes
			count=0
			for pid in $pids 
			do
				count=`expr $count + 1`
			done
			
			json_add_string "pids" "$pids"
			json_add_int "running" $count
		elif [ "$argument" == "-stop" ]
		then 
			# stop the shellinabox daemon
			Log "ShellinaboxCtrl:: Stop the shellinabox daemon"

			# stop shellinaboxd
			/etc/init.d/shellinabox stop

			json_add_int "stopped" 1
		elif [ "$argument" == "-restart" ]
		then 
			# stop the shellinabox daemon
			Log "ShellinaboxCtrl:: Stop the shellinabox daemon"

			# stop shellinaboxd
			/etc/init.d/shellinabox restart

			json_add_int "restart" 1
		else
			# unsupported command, do nothing
			Log "ShellinaboxCtrl:: unsupported command: $argument"
		fi
	done

	# output the json
	json_dump
}

# function to find wifi info and return it all in one go
GetWifiInfo () {
	# parse the arguments object
	local argumentString=$(_ParseArgumentsObject)
	Log "argument string: $argumentString"
	
	# read the network type
	bRead=0
	for argument in $argumentString
	do
		if [ "$argument" == "-type" ]
		then
			bRead=1
			continue
		fi
		if [ $bRead -eq 1 ]
		then
			networkType="$argument"
			bRead=0
		fi
	done

	if 	[ "$networkType" == "ap" ] ||
		[ "$networkType" == "sta" ];
	then
		# find the intf id's
		intfAp=-1
		intfSta=-1
		intfId=-1
		intfType=""
		CheckCurrentUciWifi

		if [ "$networkType" == "ap" ]; then
			intfId=$intfAp
			intfType="wlan"
		elif [ "$networkType" == "sta" ]; then
			intfId=$intfSta
			intfType="wwan"
		fi

		# fetch all of the wifi network data for that id
		json_init

		if [ $intfId -ge 0 ]
		then
			local iface=$(uci -q get wireless.\@wifi-iface[$intfId])
			if [ "$iface" == "wifi-iface" ]; then 
				json_add_string "ssid" $(uci -q get wireless.\@wifi-iface[$intfId].ssid)
				json_add_string "encryption" $(uci -q get wireless.\@wifi-iface[$intfId].encryption)
				json_add_string "password" $(uci -q get wireless.\@wifi-iface[$intfId].key)
				json_add_string "mode" $(uci -q get wireless.\@wifi-iface[$intfId].mode)
				json_add_string "ip" $(uci -q get network.$intfType.ipaddr)
				json_add_string "netmask" $(uci -q get network.$intfType.netmask)
				json_add_boolean "enabled" 1
			fi
		else
			json_add_boolean "enabled" 0
			json_add_string "mode" "$networkType"
		fi

		# output the json
		json_dump
	fi
}


########################
##### Main Program #####

appLocation="/www/apps"

cmdAppList="app-list"
cmdShellinabox="shellinabox"
cmdWifiInfo="wifi-info"
cmdStatus="status"

jsonAppList='"'"$cmdAppList"'": { }'
jsonShellinabox='"'"$cmdShellinabox"'": { "params": { "key": "value" } }'
jsonWifiInfo='"'"$cmdWifiInfo"'": { "params": { "key": "value" } }'
jsonStatus='"'"$cmdStatus"'": { }'


case "$1" in
    list)
		echo "{ $jsonAppList, $jsonShellinabox, $jsonWifiInfo, $jsonStatus }"
    ;;
    call)
		Log "Function: call, Method: $2"

		case "$2" in
			$cmdAppList)
				# run the app-list scan
				AppList "$appLocation"
			;;
			$cmdShellinabox)
				# read the json arguments
				read input;
				Log "Json argument: $input"

				# parse the json
				json_load "$input"

				# parse the json and run the function
				ShellinaboxCtrl
			;;
			$cmdWifiInfo)
				# read the json arguments
				read input;
				Log "Json argument: $input"

				# parse the json
				json_load "$input"

				# parse the json and run the function
				GetWifiInfo
			;;
			$cmdStatus)
				# dummy call for now
				echo '{"status":"good"}'
		;;
		esac
    ;;
esac

# take care of the log file
CloseLog
