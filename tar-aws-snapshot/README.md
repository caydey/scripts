# tar-aws-snapshot

Create incremental, compressed, encrypted, tar snapshots, automatically uploaded to AWS S3 Glacier Deep Storage

# Configuration

Run the script to create the configuration files, located at `/root/tar-snapshot-config`

## secrets.config

- `AWS_ACCESS_KEY_ID` IAM access key id
- `AWS_SECRET_ACCESS_KEY` IAM access key
- `AWS_DEFAULT_REGION` region of bucket
- `AWS_BUCKET_NAME` bucket name
- `SECRET_MASTER_KEY` password to encrypt files with
- `SECRET_MASTER_KEY_HINT` password hint (such as argon2 parameters) that is added to the tags of uploaded AWS files

## injectors.sh

Functions must start with `injector_` and are called with the parameter "$1" which specifies the directory that will be added to the created tarball in its `/injected` directory.

## exclude.list

Contains a list of files to exclude, asterisks `*` match backslashes `/`. Files inside the configuration directory that match `exclude*.list` are also included.

## include.list

Files to include in archive

# AWS Pricing

AWS Glacier Deep Archive costs [$0.00099 per GB/month](https://aws.amazon.com/s3/pricing/).
That is equivalent to which is $1.20 per 100 GB/year
