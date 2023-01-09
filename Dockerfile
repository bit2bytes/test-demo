ARG BASE_IMAGE=iregistry.eur.ad.sag/halley-snaps/dev-tools:ubi-java8
ARG DCC_IMAGE_SRC=iregistry.eur.ad.sag/halley-snaps/webmethods-b2b-dcc2:10.15.2_snapshot_latest
ARG DCC_IMAGE_DEST=iregistry.eur.ad.sag/halley-snaps/webmethods-b2b-dcc2:10.15.2_snapshot_latest
ARG TARGET_IMAGE=iregistry.eur.ad.sag/ibit/ubi8:jdk11-ubi

FROM $DCC_IMAGE_SRC as dccImageSrc
FROM $DCC_IMAGE_DEST as dccImageDest

FROM $BASE_IMAGE as gbuilder
  #RUN yum install -y git java-1.8.0-openjdk-devel which
  RUN microdnf install git tar
  RUN export GIT_SSL_NO_VERIFY=1 && git clone https://github.softwareag.com/innsh/k8s-util.git
  RUN chmod 744 k8s-util/gradlew && \
    cd k8s-util && \
    ./gradlew build && \
    tar -C / -xf build/distributions/k8s-util-2.0.tar 

FROM dtr.eur.ad.sag:4443/ibit/centos:7-20190801_approved as mvnbuilder
  RUN yum install -y which java-11-openjdk-devel  
  RUN mkdir -p /opt/software/sag-upgrade-manager
  COPY ./ /opt/softwareag/sag-upgrade-manager
  RUN cd /opt/softwareag/sag-upgrade-manager && \
    sed -i -e 's/\r$//' mvnw && \
	./mvnw package

FROM $TARGET_IMAGE
  ENV SAG_HOME=/opt/softwareag/ \
    DCC_HOME_SRC=/common/db/bin/ \
    DCC_HOME_DEST=/dcc_dest/common/db/bin/ \
    K8S_UTIL_HOME=/k8s-util-2.0

  USER root
  RUN microdnf install yum 
      #yum install -y https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm && \
  RUN yum install -y https://repo.mysql.com//mysql80-community-release-el8-3.noarch.rpm  
  RUN yum update -y 
  RUN yum install -y mysql-community-client 
  RUN yum autoremove && yum clean all 
  RUN rm -rf /var/log/* /var/cache/yum

  RUN mkdir -p /opt/SAGUpgradeManager/logs
  RUN chown -R 1724:1724 /opt/SAGUpgradeManager

  USER 1724


  VOLUME $SAG_HOME/common/db/logs
  VOLUME $SAG_HOME/dcc_dest/common/db/logs
  VOLUME /opt/SAGUpgradeManager/logs

  COPY --chown=1724:1724 --from=dccImageSrc $SAG_HOME $SAG_HOME
  COPY --chown=1724:1724 --from=dccImageDest $SAG_HOME $SAG_HOME/dcc_dest
  COPY --chown=1724:1724 --from=gbuilder $K8S_UTIL_HOME $K8S_UTIL_HOME


  # Refer to Maven build -> finalName
  ARG JAR_FILE=$SAG_HOME/sag-upgrade-manager/um-api/target/um-api-0.0.1-SNAPSHOT.jar
  ARG SCRIPTS_FOLDER=$SAG_HOME/sag-upgrade-manager/scripts

  WORKDIR /opt/SAGUpgradeManager

  COPY --chown=1724:1724 --from=mvnbuilder ${JAR_FILE} sag-upgrade-manager.jar
  COPY --chown=1724:1724 --from=mvnbuilder ${SCRIPTS_FOLDER} scripts

  CMD java -jar /opt/SAGUpgradeManager/sag-upgrade-manager.jar
