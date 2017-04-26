# docker-vsftpd-s3

Alpine based Dockerfile running a vsftpd server providing FTP access to an Amazon S3 bucket.
This docker image can run in Amazon ECS.

## Usage

Following environment variables can be customized.

```shell
AWS_ACCESS_KEY_ID=               # acces key of the AWS user, required
AWS_SECRET_ACCESS_KEY=           # secret key of the AWS user, required
S3_BUCKET=                       # the S3 bucket name, required
S3_ACL=private                   # default to private, optional
FTP_USER=s3ftp                   # the ftp user, default to s3ftp, optional
FTP_PASS=s3ftp                   # the ftp password, default to s3ftp, optional
CMDS_ALLOWED=                    # the ftp allowed commands, default to upload only, no delete or download, optional
PASV_ADDRESS=                    # the ftp server external IP address, default to the AWS instance public IP, optional
PASV_MIN_PORT=65000              # the ftp server pasv_min_port, default to 65000, optional
PASV_MAX_PORT=65000              # the ftp server pasv_max_port, default to 65000, optional
```

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
$ docker run -it --device /dev/fuse --cap-add sys_admin -p 21:21 -p 65000:65000 -e AWS_ACCESS_KEY_ID=ABCDEFGHIJKLMNOPQRST -e AWS_SECRET_ACCESS_KEY=0123456789ABCDEF0123456789ABCDEF01234567 -e S3_BUCKET="my-s3-bucket" -e FTP_USER="my_ftp_user" -e FTP_PASS="my_ftp_password" vsftpd-s3
```

