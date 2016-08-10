#!/usr/bin/env bash

# Color Reset
	Color_Off="\033[0m"       # Text Reset

# Regular Colors
	Black="\033[0;30m"        # Black
	Red="\033[0;31m"          # Red
	Green="\033[0;32m"        # Green
	Yellow="\033[0;33m"       # Yellow
	Blue="\033[0;34m"         # Blue
	Purple="\033[0;35m"       # Purple
	Cyan="\033[0;36m"         # Cyan
	White="\033[0;37m"        # White

# Bold
	BBlack="\033[1;30m"       # Black
	BRed="\033[1;31m"         # Red
	BGreen="\033[1;32m"       # Green
	BYellow="\033[1;33m"      # Yellow
	BBlue="\033[1;34m"        # Blue
	BPurple="\033[1;35m"      # Purple
	BCyan="\033[1;36m"        # Cyan
	BWhite="\033[1;37m"       # White

#function log {
#  echo -e "-- $1 [ ${Yellow}14m${Color_Off} ]\n"
#}

backupuser="joachim"

if [ $(id -u) = "0" ]; then
  sudo -u $backupuser $0
  exit 0
fi

# force log writing
name=$(date +%Y-%m-%d_%H%M)
log=log-$name

if [[ $# -eq 0 ]]; then
  mkdir -p logs
  $0 bar 2>&1 | tee -a logs/$log
  exit 0
fi


if [ -f .pid ]; then
  read pid < .pid
  #echo $pid
  ps -p $pid > /dev/null
  r=$?
  if [ $r -eq 0 ]; then
    echo "$pid is currently running, not executing $0 twice, exiting now..."
    exit 1
  fi
fi

echo $$ > .pid

timerStart=`date +%s`

function t {
	timerLastPhase=`date +%s`
	difftimelps=$(($timerLastPhase-$timerStart))
	tString="$(($difftimelps / 60))m $(($difftimelps % 60))s" 

        echo -e "[ ${Yellow} $tString ${Color_Off} ] ${Green} $1 ${Color_Off}\n"
}

t "creating rsync backup"

rsync -avz --progress --partial --delete --delete-excluded --exclude={"/home/joachim/irclogs/*","/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} nixcloud:/ backup-rsync

rsync_ret=$?

if [ "$rsync_ret" != "0" ] && [ "$rsync_ret" != "24" ]; then
	echo "rsync error code: $rsync_ret, exiting"
	exit 1
fi

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes 
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
mkdir -p .borg-cache
export BORG_CACHE_DIR=.borg-cache

if [ ! -d backup-borg ]; then
	t "initially creating borg archive"
	borg init -v -e none backup-borg 

	borg_ret=$?
	if [ "$borg_ret" != "0" ]; then
		echo "borg error: error with creating new archive, exiting"
		exit 1
	fi
fi

t "adding files to borg backup"

borg create -v --stats backup-borg::$name backup-rsync

borg_ret=$?
if [ "$borg_ret" != "0" ]; then
	echo "borg error, exiting"
	exit 1
fi

t "consolidating backups"

borg prune --keep-within=10d --keep-weekly=4 --keep-monthly=-1 backup-borg

borg_ret=$?
if [ "$borg_ret" != "0" ]; then
	echo "CRITICAL! borg archive consolidation failed, exiting"
	exit 1
else
	echo "borg: archive consolidation done."
fi

t "checking archive integrity"

borg check backup-borg/

borg_ret=$?
if [ "$borg_ret" != "0" ]; then
	echo "CRITICAL! borg archive error found, exiting"
	exit 1
else
	echo "borg: archive is alright."
fi


t "list all backups in archive"

borg list backup-borg/
 
t "reporting to monitoring"
# FIXME reporting needs to be implemented
# nagios

echo "backup finished successfully!"
rm .pid
exit 0
