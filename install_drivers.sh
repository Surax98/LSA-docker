#!/bin/bash
#edit the baseurl if they change it, for whatever reason
BASEURL="https://docs.broadcom.com/docs-and-downloads"
VERSION="8.10.0.5.0-1_MR8.10"
PARTIAL_VERSION="8.10.0.5.0"

wget ${BASEURL}/${VERSION}_Linux%20Driver.zip && \
	unzip ${VERSION}_Linux\ Driver.zip && \
	cd linuxdrvr_rel && tar -zxvf mpi3mr-release.tar.gz && \
	tar -zxvf mpi3mr-${PARTIAL_VERSION}-src.tar.gz && cd mpi3mr && \
	sudo ./compile.sh

sudo mkdir -p /usr/local/bin/megaraid_driver
sudo chown $USER:$USER /usr/local/bin/megaraid_driver
cp load.sh uload.sh *.o *.ko /usr/local/bin/megaraid_driver

read -p "Do you want to create a Systemd service to automatically load the driver at startup? (Y/N): " response
response=$(echo "$response" | tr '[:lower:]' '[:upper:]')

if [[ "$response" == "Y" ]]; then
    echo "[Unit]
    Description=Loading MegaRaid driver

    [Service]
    Type=simple
    ExecStart=/usr/local/bin/megaraid_driver/load.sh
    Restart=on-failure
    User=nobody
    Group=nogroup

    [Install]
    WantedBy=multi-user.target" > tmp.srv
    
    sudo mv tmp.srv /etc/systemd/system/megaraid_load_driver.service
    sudo systemctl daemon-reload
    sudo systemctl start megaraid_load_driver.service
    sudo systemctl enable megaraid_load_driver.service

else

    echo "To load the driver module, run the load.sh in the megaraid_driver directory.\nThis is mandatory and must done everytime you reboot the system."
    
fi 

cd ../.. 
rm -rf linuxdrvr_rel ${VERSION}_Linux\ Driver.zip