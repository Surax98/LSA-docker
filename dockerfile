FROM ubuntu:jammy AS builder

ARG LSA_VERSION=""
ENV BASEURL="https://docs.broadcom.com/docs-and-downloads"
ENV ARCH="Linux"

# Install base dependencies and Selenium requirements
RUN apt-get update && \
	apt-get install -y \
		wget \
		unzip \
		python3 \
		python3-pip \
		# Chrome dependencies
		ca-certificates \
		fonts-liberation \
		libasound2 \
		libatk-bridge2.0-0 \
		libatk1.0-0 \
		libcups2 \
		libdbus-1-3 \
		libdrm2 \
		libgbm1 \
		libgtk-3-0 \
		libnspr4 \
		libnss3 \
		libxcomposite1 \
		libxdamage1 \
		libxfixes3 \
		libxkbcommon0 \
		libxrandr2 \
		xdg-utils \
	&& rm -rf /var/lib/apt/lists/*

# Install Google Chrome (not snap version) and matching ChromeDriver
RUN wget -q -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
	apt-get update && \
	apt-get install -y /tmp/google-chrome.deb && \
	rm /tmp/google-chrome.deb && \
	rm -rf /var/lib/apt/lists/* && \
	# Get Chrome version and download matching ChromeDriver
	CHROME_VERSION=$(google-chrome --version | grep -oP '\d+\.\d+\.\d+\.\d+') && \
	echo "Chrome version: $CHROME_VERSION" && \
	wget -q -O /tmp/chromedriver.zip "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chromedriver-linux64.zip" && \
	unzip -q /tmp/chromedriver.zip -d /tmp && \
	mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/ && \
	chmod +x /usr/local/bin/chromedriver && \
	rm -rf /tmp/chromedriver* && \
	chromedriver --version

# Install Python Selenium
RUN pip3 install --no-cache-dir selenium

# Copy the version detection script
COPY get_latest_version.py /tmp/get_latest_version.py
RUN chmod +x /tmp/get_latest_version.py

# Detect or use provided version
RUN if [ -z "$LSA_VERSION" ]; then \
		echo "Detecting LSA version with Selenium..." && \
		export VERSION=$(python3 /tmp/get_latest_version.py 2>&1 | tee /tmp/version_detection.log | tail -1) && \
		cat /tmp/version_detection.log >&2; \
	else \
		export VERSION="$LSA_VERSION"; \
	fi && \
	echo "Using LSA version: $VERSION" && \
	mkdir /MSM && \
	wget -O /MSM.zip ${BASEURL}/${VERSION}_LSA_${ARCH}.zip && \
	unzip -d /MSM /MSM.zip && \
	cd /MSM && \
	find . -iname '*.zip' -exec sh -c 'unzip -o -d "${0%.*}" "$0"' '{}' ';' && \
	find . -iname '*.zip' -delete

# Final stage
FROM ubuntu:jammy

ENV PASSWORD="password"
ENV WEB_PORT="2463"
ENV LSA_PORT="9000"
ENV TERM=xterm
ENV DEBIAN_FRONTEND=noninteractive

RUN apt -y update && \
	apt -y install --no-install-recommends libldap2-dev libgssapi3-heimdal wget && \
	wget -q http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb && \
	wget -q http://archive.ubuntu.com/ubuntu/pool/main/o/openldap/libldap-common_2.4.49+dfsg-2ubuntu1_all.deb && \
	wget -q http://archive.ubuntu.com/ubuntu/pool/main/o/openldap/libldap-2.4-2_2.4.49+dfsg-2ubuntu1_amd64.deb && \
	dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb && \
	dpkg -i libldap-common_2.4.49+dfsg-2ubuntu1_all.deb && \
	dpkg -i libldap-2.4-2_2.4.49+dfsg-2ubuntu1_amd64.deb && \
	rm -f *.deb && \
	apt -y remove wget && \
	apt -y autoremove && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY entrypoint.sh /
COPY LsiSASH /
RUN chmod +x /entrypoint.sh

COPY --from=builder /MSM/webgui_rel/LSA_Linux/gcc_11.2.x /MSM/webgui_rel/LSA_Linux/gcc_11.2.x

WORKDIR /MSM/webgui_rel/LSA_Linux/gcc_11.2.x

RUN dpkg -i LSA_lib_utils2-9.00-1_amd64.deb && \
	chmod +x ./RunDEB.sh && \
	bash install_deb.sh -s $WEB_PORT $LSA_PORT 2 && \
	cp /LsiSASH /etc/init.d/LsiSASH && \
	mkdir -p /usr/local/var/log/ && \
	touch /usr/local/var/log/slpd.log && \
	mv /opt/lsi/LSIStorageAuthority /opt/lsi/backup && \
	cd / && \
	rm -rf /MSM

WORKDIR /

ENTRYPOINT ["/entrypoint.sh"]