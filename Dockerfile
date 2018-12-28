FROM amazonlinux:latest
RUN yum update -y && \
yum -y install -y gcc dialog augeas-libs openssl-devel \
       ca-certificates python-pip zip
RUN pip install virtualenv awscli
CMD bash /lambda/build.sh