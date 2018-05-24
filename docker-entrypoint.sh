#!/bin/ash
set -euo pipefail
set -o errexit

trap 'kill -SIGQUIT $PID' INT

# VSFTPD PASV configuration
PASV_ADDRESS=${PASV_ADDRESS:-$(timeout -t 1 wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null ||:)}
PASV_MIN_PORT=${PASV_MIN_PORT:-65000}
PASV_MAX_PORT=${PASV_MAX_PORT:-65000}

# VSFTPD Banner
FTPD_BANNER=${FTPD_BANNER:-1001Pharmacies FTP Server}

# FTP allowed commands
# full command list : https://blog.vigilcode.com/2011/08/configure-secure-ftp-with-vsftpd/
CMDS_ALLOWED=${CMDS_ALLOWED:-ABOR,ALLO,APPE,CCC,CDUP,CWD,DELE,EPSV,FEAT,HELP,LIST,LPSV,MKD,MLST,MODE,NLST,NOOP,OPTS,PASS,PASV,PBSZ,PORT,PWD,QUIT,REIN,REST,RETR,RMD,RNFR,RNTO,SITE,SIZE,STAT,STOR,STRU,SYST,TYPE,USER}

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

# SSL certificate
SSL_CERT_C=${SSL_CERT_C:-FR}
SSL_CERT_ST=${SSL_CERT_ST:-Herault}
SSL_CERT_L=${SSL_CERT_L:-Montpellier}
SSL_CERT_O=${SSL_CERT_O:-1001Pharmacies}
SSL_CERT_OU=${SSL_CERT_OU:-Hosting}
SSL_CERT_CN=${SSL_CERT_CN:-ftp.1001pharmacies.com}

# Create SSL certificate
openssl req -x509 -nodes -days 365 -newkey rsa:1024 -subj "/C=${SSL_CERT_C}/ST=${SSL_CERT_ST}/L=${SSL_CERT_L}/O=${SSL_CERT_O}/OU=${SSL_CERT_OU}/CN=${SSL_CERT_CN}" -keyout /etc/ssl/private/vsftpd.pem -out /etc/ssl/private/vsftpd.pem 2>/dev/null && echo "
rsa_cert_file=/etc/ssl/private/vsftpd.pem
rsa_private_key_file=/etc/ssl/private/vsftpd.pem
ssl_enable=YES
allow_anon_ssl=YES
force_anon_data_ssl=NO
force_anon_logins_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=YES
ssl_sslv3=YES
require_cert=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH" >> /etc/vsftpd.conf

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
FTPD_USERS=${FTPD_USERS:-${FTPD_USER}::${FTPD_PASS}::${S3_BUCKET}::${AWS_ACCESS_KEY_ID}::${AWS_SECRET_ACCESS_KEY}}

# For each user
echo "${FTPD_USERS}" |sed 's/ /\n/g' |while read line; do
  echo ${line//::/ } |while read ftpd_user ftpd_pass s3_bucket aws_access_key_id aws_secret_access_key; do

    # Create FTP user
    adduser -h /home/${ftpd_user} -s /sbin/nologin -D ${ftpd_user}
    echo "${ftpd_user}:${ftpd_pass:-$FTPD_PASS}" | chpasswd 2> /dev/null

    # Configure s3fs
    echo "${aws_access_key_id:-$AWS_ACCESS_KEY_ID}:${aws_secret_access_key:-$AWS_SECRET_ACCESS_KEY}" > /home/${ftpd_user}/.passwd-s3fs
    chmod 0400 /home/${ftpd_user}/.passwd-s3fs

    # Mount s3fs
    /usr/bin/s3fs ${s3_bucket:-$S3_BUCKET} /home/${ftpd_user} -o nosuid,nonempty,nodev,allow_other,complement_stat,mp_umask=027,uid=$(id -u ${ftpd_user}),gid=$(id -g ${ftpd_user}),passwd_file=/home/${ftpd_user}/.passwd-s3fs,default_acl=${S3_ACL},retries=5

    # Exit docker if the s3 filesystem is not reachable anymore
    ( crontab -l && echo "* * * * * timeout -t 3 touch /home/${ftpd_user}/.test >/dev/null 2>&1 || kill -TERM -1" ) | crontab -

  done
done

# Enable SFTP
echo "Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
UseDNS no
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding no
Subsystem sftp internal-sftp
ForceCommand internal-sftp -d %u
ChrootDirectory /home
" > /etc/ssh/sshd_config

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

# Launch sshd && vsftpd
[ $# -eq 0 ] && /usr/sbin/sshd -e && /usr/sbin/vsftpd || exec "$@" &
PID=$! && wait
