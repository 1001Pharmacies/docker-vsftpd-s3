# docker-vsftpd-s3

Alpine based Dockerfile running a vsftpd server providing secure FTP access to an Amazon S3 bucket.
This docker image can run in Amazon ECS.

## Usage

Following environment variables can be customized.

```shell
AWS_ACCESS_KEY_ID=               # acces key of the AWS user, required
AWS_SECRET_ACCESS_KEY=           # secret key of the AWS user, required
S3_BUCKET=                       # the S3 bucket name, required
S3_ACL=private                   # default to private, optional
FTPD_USER=s3ftp                  # the ftp user, default to s3ftp, optional
FTPD_PASS=s3ftp                  # the ftp password, default to s3ftp, optional
FTPD_BANNER=                     # the ftp banner
CMDS_ALLOWED=                    # the ftp allowed commands, default to upload only, no delete or download, optional
PASV_ADDRESS=                    # the ftp server external IP address, default to the AWS instance public IP, optional
PASV_MIN_PORT=65000              # the ftp server pasv_min_port, default to 65000, optional
PASV_MAX_PORT=65000              # the ftp server pasv_max_port, default to 65000, optional
FTP_SYNC=                        # enable file synchronisation with a remote ftp server
FTP_HOST=                        # the remote ftp server to sync with
FTP_USER=                        # the ftp user to connect to remote ftp server
FTP_PASS=                        # the ftp password to connect to remote ftp server
REMOTE_DIR=                      # the directory to sync from on the remote ftp server, default to /
LOCAL_DIR=                       # the directory to sync to on the local server, default to /home/$FTPD_USER
```

When you need multiple FTPD_USERs to serve multiple S3_BUCKETs, you have to set all variables at once in a list of double twopoints separated values.

FTPD_USERS="FTPD_USER_1::FTPD_PASS_1::S3_BUCKET_1::AWS_ACCESS_KEY_ID_1::AWS_SECRET_ACCESS_KEY_1 FTPD_USER_2::FTPD_PASS_2::S3_BUCKET_2::AWS_ACCESS_KEY_ID_2::AWS_SECRET_ACCESS_KEY_2 ..."

You can specify values in FTPD_PASS, S3_BUCKET, AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY that will be use as default for FTPD_USERS.

FTPD_USERS="FTPD_USER_1::FTPD_PASS_1::S3_BUCKET_1::AWS_ACCESS_KEY_ID_1::AWS_SECRET_ACCESS_KEY_1 FTPD_USER_2::FTPD_PASS_2::S3_BUCKET_2 FTPD_USER_3 FTPD_USER_4::FTPD_PASS_4"

## AWS Notes

### IAM User

You should create an IAM User with a dedicated access/secret key pair to access your S3 bucket and create a specific strategy attached to this user. 

```json
{
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::my-bucket",
                "arn:aws:s3:::my-bucket/*"
            ]
        }
    ]
}
```

### ELB/ECS Compatibility

You can set an ELB listening on port 21 and forwarding requests to sftpd-s3 dockers running in an ECS cluster.

### Security groups

You should allow access on port 21 and port 65000 at least on the instances running sftpd-s3 dockers and on the attached ELB.

## Example

Build a docker image named "vsftpd-s3".

```shell
$ docker build -t vsftpd-s3 .
```

Start a docker from this image.

```shell
$ docker run -it --device /dev/fuse --cap-add sys_admin --security-opt apparmor:unconfined -p 21:21 -p 65000:65000 -e AWS_ACCESS_KEY_ID=ABCDEFGHIJKLMNOPQRST -e AWS_SECRET_ACCESS_KEY=0123456789ABCDEF0123456789ABCDEF01234567 -e S3_BUCKET="my-s3-bucket" -e FTPD_USER="my_ftp_user" -e FTPD_PASS="my_ftp_password" vsftpd-s3
```

## Security notes

Current docker image is shipped with FTPS and SFTP support, although SFTP support should be (and will be !) shipped in a separate docker image.
SFTP is served by openssh listening on port 22. SFTP is not properly configured to chroot users in their homedir.
This allows an authenticated user to leak the list of your ftp users.

