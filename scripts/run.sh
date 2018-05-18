#!/bin/bash

sudo rc-update
sudo rc-status
sudo touch /run/openrc/softlevel
sudo /etc/init.d/sshd restart
/opt/elasticsearch/bin/elasticsearch
