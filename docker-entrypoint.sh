#!/bin/ash
set -euo pipefail
set -o errexit
IFS=$'\n\t'

# Amazon S3 bucket
S3_ACL=${S3_ACL:-private}
S3_BUCKET=${S3_BUCKET:-s3bucket}
# Amazon credentials
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-aws_access_key_id}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-aws_secret_access_key}

# FTP credentials
FTP_USER=${FTP_USER:-s3ftp}
FTP_PASS=${FTP_PASS:-s3ftp}
# FTP PASV configuration
PASV_ADDRESS=${PASV_ADDRESS:-$(timeout -t 1 wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null ||:)}
PASV_MIN_PORT=${PASV_MIN_PORT:-65000}
PASV_MAX_PORT=${PASV_MAX_PORT:-65000}

# FTP allowed commands
# full command list : https://blog.vigilcode.com/2011/08/configure-secure-ftp-with-vsftpd/
CMDS_ALLOWED=${CMDS_ALLOWED:-ABOR,ALLO,APPE,CCC,CDUP,CWD,LIST,MKD,MLST,MODE,NLST,NOOP,OPTS,PASS,PASV,PBSZ,PWD,QUIT,REIN,REST,RNFR,RNTO,SITE,SIZE,STAT,STOR,STRU,SYST,TYPE,USER}

# Create FTP user
adduser -h /home/${FTP_USER} -s /sbin/nologin -D ${FTP_USER}
echo "${FTP_USER}:${FTP_PASS}" | chpasswd 2> /dev/null
# Configure s3fs
echo "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" > /etc/passwd-s3fs
chmod 0400 /etc/passwd-s3fs
# Configure vsftpd
echo "anonymous_enable=NO
seccomp_sandbox=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
cmds_allowed=$CMDS_ALLOWED
pasv_enable=YES
pasv_promiscuous=YES
pasv_min_port=$PASV_MIN_PORT
pasv_max_port=$PASV_MAX_PORT" > /etc/vsftpd.conf
[ -n "$PASV_ADDRESS" ] && echo "pasv_address=$PASV_ADDRESS" >> /etc/vsftpd.conf

# Mount s3fs
/usr/bin/s3fs ${S3_BUCKET} /home/${FTP_USER} -o nosuid,nonempty,nodev,allow_other,default_acl=${S3_ACL},retries=5

# Launch vsftpd
[ $# -eq 0 ] && vsftpd || exec "$@"
