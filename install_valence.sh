#!/bin/bash
#title           :install_valence.sh
#description     :This script will install valence package and deploys conf files
#author          :Intel Corporation
#date            :17-10-2016
#version         :0.1
#usage           :sudo -E bash install_valence.sh
#notes           :Run this script as sudo user and not as root.
#                 This script is needed still valence is packaged in to .deb/.rpm
#==============================================================================

install_log=install_valence.log
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CURR_USER="$(whoami)"

cd "$DIR"
echo "Current directory: $DIR" >> $install_log
if [ "$CURR_USER" != 'root' ]; then
    echo "You must be root to install."
    exit
fi

PYHOME="/usr/local/bin"
echo "Detected PYTHON HOME: $PYHOME" >> $install_log

# Copy the config files
echo "Setting up valence config" >> $install_log
sed "s/\${CHUID}/$CURR_USER/"  "$DIR"/doc/source/init/valence.conf > /tmp/valence.conf
# Use alternate sed delimiter because path will have /
sed -i "s#PYHOME#$PYHOME#" /tmp/valence.conf
mv /tmp/valence.conf /etc/init/valence.conf

# create conf directory for valence if it doesn't exist
if [ ! -d "/etc/valence" ]; then
    mkdir /etc/valence
fi
chown "$CURR_USER":"$CURR_USER" /etc/valence
cp etc/valence/valence.conf.sample /etc/valence/valence.conf

# create log directory for valence if it doesn't exist
if [ ! -d "/var/log/valence" ]; then
    mkdir /var/log/valence
fi
chown "$CURR_USER":"$CURR_USER" /var/log/valence

echo "Installing dependencies from requirements.txt" >> $install_log
pip install -r requirements.txt

echo "Installing the etcd database" >> $install_log
ETCD_VER=v3.1.2
DOWNLOAD_URL=https://github.com/coreos/etcd/releases/download
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
mkdir -p /var/etcd && tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /var/etcd --strip-components=1
chown "$CURR_USER":"$CURR_USER" /var/etcd
mv /var/etcd/etcd /usr/local/bin/etcd && mv /var/etcd/etcdctl /usr/local/bin/etcdctl

sed "s/\${CHUID}/$CURR_USER/"  "$DIR"/doc/source/init/etcd.conf > /etc/init/etcd.conf

echo "Starting etcd database" >> $install_log
service etcd start
sleep 2
timeout=30
attempt=1
until [[ $(service etcd status) = "etcd start/running"* ]]
do
  sleep 1
  attempt=$((attempt+1))
  if [[ $attempt -eq timeout ]]
  then
    echo "Database failed to start, aborting installation."
    rm -rf /var/etcd /usr/local/bin/etcd /usr/local/bin/etcdctl
    exit
  fi
done

echo "Adding database directories" >> $install_log
etcdctl --endpoints=127.0.0.1:2379 mkdir /nodes
etcdctl --endpoints=127.0.0.1:2379 mkdir /flavors
etcdctl --endpoints=127.0.0.1:2379 mkdir /pod_managers

echo "Invoking setup.py" >> $install_log
python setup.py install
if [ $? -ne 0 ]; then
    echo "ERROR: setup.py failed. Please check $install_log for details.
          Please fix the error and retry."
    exit
fi

echo "Installation Completed"
echo "To start valence : sudo service valence start"