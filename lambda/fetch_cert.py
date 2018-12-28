
import datetime
import os
import socket
import ssl
import botocore
import boto3
import certbot.main

def read_file(path):
    """Simple function to open a file and return the contents."""
    with open(path, 'r') as f:
        contents = f.read()
    return contents

def provision_cert(email, domain_name):
    """Use certbot to request a certificate in non-interactive mode, using route53 to answer the ownership challange. The standard certbot logging and configuration directories are owned by root, so we specifiy /tmp"""
    temp_dir = "/tmp"
    certbot.main.main([
        'certonly',
        '-n',
        '--agree-tos',
        '--email', email,
        '--dns-route53',
        '-d', domain_name,
        '--config-dir', temp_dir,
        '--work-dir', temp_dir,
        '--logs-dir', temp_dir,
    ])

    path = '/tmp/live/' + domain_name + '/'
    return {
        'cert.pem': path + 'cert.pem',
        'privkey.pem': path + 'privkey.pem',
        'chain.pem': path + 'chain.pem',
        'fullchain.pem': path + 'fullchain.pem'
    }

def ssl_expiry_datetime(domain_name):
    """Fetch the expire date of the certificate in use"""
    ssl_date_fmt = r'%b %d %H:%M:%S %Y %Z'
    context = ssl.create_default_context()
    conn = context.wrap_socket(
        socket.socket(socket.AF_INET),
        server_hostname=domain_name,
    )
    conn.settimeout(3.0)

    conn.connect((domain_name, 443))
    ssl_info = conn.getpeercert()
    # parse the string from the certificate into a Python datetime object
    return datetime.datetime.strptime(ssl_info['notAfter'], ssl_date_fmt)

def ssl_valid_time_remaining(domain_name):
    """Get the number of days before cert expires."""
    expires = ssl_expiry_datetime(domain_name)
    print("SSL cert for %s expires at %s" % (domain_name, expires.isoformat()))
    return expires - datetime.datetime.utcnow()


def should_provision(domain_name, buffer_days=30):
    """Check if `domain_name` SSL cert expires is within `buffer_days`."""
    remaining = ssl_valid_time_remaining(domain_name)

    # if the cert expires in less than a month, reissue it
    if remaining < datetime.timedelta(days=0):
        # cert has already expired - uhoh! somebondy's in trouble.
        print("Cert expired %s days ago" % remaining.days)
        return True
    elif remaining < datetime.timedelta(days=buffer_days):
        # expires sooner than the buffer
        return True
    else:
        # everything is fine
        print "Cert does not need to be provisioned"
        return False

def notify_via_sns(topic_arn, domain_name):
    """Publish to SNS that we have issued a new certificate"""
    # TODO: Add falire notification logic
    sns_client = boto3.client('sns')
    sns_client.publish(TopicArn=topic_arn,
        Subject='Issued new SSL certificate',
        Message='Issued new certificates for: ' + domain_name
    )

def publish_s3(bucket, domain, cert):
    """Publish certificate files to S3"""
    s3_client = boto3.client('s3')
    for key, value in cert.iteritems():
        print "Uploading %s to S3" % key
        s3_client.upload_file(value, bucket, domain + "_cert/" + key,
                              ExtraArgs={'ACL':'bucket-owner-full-control'})

def handler(event, context):
    try:
        domain_name = os.environ['DOMAIN']
        print domain_name
        if should_provision(domain_name):
            cert = provision_cert(os.environ['DOMAIN_EMAIL'], domain_name)
            publish_s3(os.environ['BUCKET'], domain_name, cert)
            notify_via_sns(os.environ['NOTIFICATION_SNS_ARN'], domain_name)
    except botocore.exceptions.ClientError as e:
        print e

# Manual invocation of the script (only used for development)
if __name__ == "__main__":
    # Test data
    test = {}

    # Test function
    handler(test, None)
