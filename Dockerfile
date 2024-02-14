ARG DRUPAL_IMAGE_VERSION
FROM drupal:${DRUPAL_IMAGE_VERSION}

LABEL maintainer="Comanche Team"

# Delete Drupal
RUN rm -fr /var/www/html/* 

#TRT12 certificate - para uso dentro da rede do TRT12
#COPY config/trt12.jus.br.crt /usr/local/share/ca-certificates/ 
#RUN update-ca-certificates

#Install necessary packages and 
RUN set -ex \
	&& buildDeps=' \
		git \
    	vim \
		curl \
		unzip \
    	mariadb-client \
        dnsutils \
        net-tools \
		' \
	&& apt-get update && apt-get install -y --no-install-recommends $buildDeps \
  	&& rm -rf /var/lib/apt/lists/* 
