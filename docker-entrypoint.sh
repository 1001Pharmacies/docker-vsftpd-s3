#!/bin/ash
set -euo pipefail
set -o errexit

# VSFTPD PASV configuration
PASV_ADDRESS=${PASV_ADDRESS:-$(timeout -t 1 wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null ||:)}
PASV_MIN_PORT=${PASV_MIN_PORT:-65000}
PASV_MAX_PORT=${PASV_MAX_PORT:-65000}

# VSFTPD Banner
FTPD_BANNER=${FTPD_BANNER:-1001Pharmacies FTP Server}

# FTP allowed commands
# full command list : https://blog.vigilcode.com/2011/08/configure-secure-ftp-with-vsftpd/
CMDS_ALLOWED=${CMDS_ALLOWED:-ABOR,ALLO,APPE,CCC,CDUP,CWD,DELE,FEAT,HELP,LIST,LPSV,MKD,MLST,MODE,NLST,NOOP,OPTS,PASS,PASV,PBSZ,PORT,PWD,QUIT,REIN,REST,RETR,RMD,RNFR,RNTO,SITE,SIZE,STAT,STOR,STRU,SYST,TYPE,USER}

# Configure vsftpd
echo "anonymous_enable=NO
seccomp_sandbox=NO
local_enable=YES
write_enable=YES
xferlog_enable=YES
log_ftp_protocol=YES
nopriv_user=vsftp
chroot_local_user=YES
allow_writeable_chroot=YES
delete_failed_uploads=YES
port_enable=YES
port_promiscuous=YES
cmds_allowed=$CMDS_ALLOWED
ftpd_banner=$FTPD_BANNER
pasv_enable=YES
pasv_promiscuous=YES
pasv_min_port=$PASV_MIN_PORT
pasv_max_port=$PASV_MAX_PORT" > /etc/vsftpd.conf
[ -n "$PASV_ADDRESS" ] && echo "pasv_address=$PASV_ADDRESS" >> /etc/vsftpd.conf

# Amazon S3 bucket
S3_ACL=${S3_ACL:-private}
S3_BUCKET=${S3_BUCKET:-s3bucket}

# Amazon credentials
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-aws_access_key_id}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-aws_secret_access_key}

# VSFTPD credentials
FTPD_USER=${FTPD_USER:-s3ftp}
FTPD_PASS=${FTPD_PASS:-s3ftp}

# Multi users
FTPD_USERS=${FTPD_USERS:-${FTPD_USER}:${FTPD_PASS}:${S3_BUCKET}:${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}}

# For each user
echo "${FTPD_USERS}" |sed 's/ /\n/g' |while read line; do
  echo ${line//:/ } |while read ftpd_user ftpd_pass s3_bucket aws_access_key_id aws_secret_access_key; do

    # Create FTP user
    adduser -h /home/${ftpd_user} -s /sbin/nologin -D ${ftpd_user}
    echo "${ftpd_user}:${ftpd_pass:-$FTPD_PASS}" | chpasswd 2> /dev/null

    # Configure s3fs
    echo "${aws_access_key_id:-$AWS_ACCESS_KEY_ID}:${aws_secret_access_key:-$AWS_SECRET_ACCESS_KEY}" > /home/${ftpd_user}/.passwd-s3fs
    chmod 0400 /home/${ftpd_user}/.passwd-s3fs

    # Mount s3fs
    /usr/bin/s3fs ${s3_bucket:-$S3_BUCKET} /home/${ftpd_user} -o nosuid,nonempty,nodev,allow_other,passwd_file=/home/${ftpd_user}/.passwd-s3fs,default_acl=${S3_ACL},retries=5

    # Exit docker if the s3 filesystem is not reachable anymore
    ( crontab -l && echo "* * * * * timeout -t 3 touch /home/${ftpd_user}/.test >/dev/null 2>&1 || kill -TERM -1" ) | crontab -

  done
done

# FTP sync client
FTP_SYNC=${FTP_SYNC:-0}
FTP_HOST=${FTP_HOST:-localhost}
DIR_REMOTE=${DIR_REMOTE:-/}
DIR_LOCAL=${DIR_LOCAL:-/home/$FTPD_USER}

# Sync remote FTP every hour (at random time to allow multiple dockers to run)
[ "$FTP_SYNC" != "0" ] \
  && MIN=$(awk 'BEGIN { srand(); printf("%d\n",rand()*60)  }') \
  && ( echo "$MIN * * * * /usr/local/bin/lftp-sync.sh $FTP_HOST $DIR_REMOTE $DIR_LOCAL/retour/\$(/bin/date +%Y/%m/%d) ^8.*$" ) | crontab -u ${FTPD_USER} - \
  && MIN=$(awk 'BEGIN { srand(); printf("%d\n",rand()*rand()*60)  }') \
  && ( crontab -u ${FTPD_USER} -l && echo "$MIN * * * * /usr/local/bin/lftp-sync.sh $FTP_HOST $DIR_REMOTE $DIR_LOCAL/facture ^INV.*$" ) | crontab -u ${FTPD_USER} - \
  && touch /var/log/lftp-sync.log \
  && chown ${FTPD_USER} /var/log/lftp-sync.log

# Launch crond
crond -L /var/log/crond.log

# Launch vsftpd
[ $# -eq 0 ] && /usr/sbin/vsftpd || exec "$@"
