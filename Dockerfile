FROM amazonlinux:latest
RUN yum update -y && \
yum -y install -y gcc dialog augeas-libs openssl-devel \
       ca-certificates python-pip zip
COPY ./fetch_cert.py /lambda/fetch_cert.py
COPY ./build.sh /
RUN pip install virtualenv awscli
CMD bash build.sh