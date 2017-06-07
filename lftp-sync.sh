#!/bin/sh

[ -d "/home/$FTPD_USER/log" ] && LOGDIR="/home/$FTPD_USER/log" || LOGDIR="/var/log"
LOG=$LOGDIR/lftp-sync.log

# lock to prevent multiple sync running together
LOCK="${TMP}/.lock-${0##*/}"
set -o noclobber
(echo "$$" > $LOCK) 2>/dev/null && trap "rm ${LOCK}; exit" HUP INT TERM || exit=255
set +o noclobber
[ ${error:-0} -ne 0 ] && echo "ERROR : $(basename $0) is LOCKED on ${HOSTNAME}. Please remove ${LOCK}" |tee -a $LOG && exit ${exit}

# check binaries
which lftp >/dev/null 2>&1 || exit 1

[ -n "$1" ] && FTP_HOST="$1"
[ -n "$2" ] && DIR_REMOTE="$2"
[ -n "$3" ] && DIR_LOCAL="$3"
[ -n "$4" ] && FILES="$4"

# check variables
[ -n "$FTP_HOST" ] && [ -n "$FTP_USER" ] && [ -n "$FTP_PASS" ] || exit 2

# check local path
[ -d ${DIR_LOCAL:-~/} ] || mkdir -p ${DIR_LOCAL:-~/} || exit 3

# Get files from the remote FTP server and remove them
lftp ftp://$FTP_USER:$FTP_PASS@$FTP_HOST << EOC
  set ftp:ssl-allow yes
  set xfer:log-file $LOG
  mirror \
    --Remove-source-files \
    -i "${FILES:-.*}" \
    ${DIR_REMOTE:-/} \
    ${DIR_LOCAL:-~/}
  quit
EOC

# unlock
rm -f "${LOCK}" 2>/dev/null && trap - HUP INT TERM

# exit
exit ${exit:-0}
