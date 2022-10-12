#!/bin/sh


apt-get update && apt-get -yq install git-core

git clone https://github.com/lomelee/AiSwitch /usr/src/AiSwitch
git clone https://github.com/signalwire/libks /usr/src/libs/libks
git clone https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp

# add build tool depend
apt-get update && apt-get -yq install --no-install-recommends build-essential cmake automake autoconf 'libtool-bin|libtool' pkg-config

# add runtime depend
apt-get update && apt-get -yq install --no-install-recommends \
libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison  libtpl-dev libtiff5-dev uuid-dev \
libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
libogg-dev libspeex-dev libspeexdsp-dev \
libldns-dev \
libavformat-dev libswscale-dev libavresample-dev \
liblua5.2-dev \
libopus-dev \
# mysql 模块编译依赖
libmariadb-dev \
# PgSQL 模块编译依赖
# libpq-dev \
libsndfile1-dev libflac-dev libogg-dev libvorbis-dev \
libshout3-dev libmpg123-dev libmp3lame-dev 


# build from source 
cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install 
cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
# 添加pgsql驱动套件编译选项（PgSQL 不在需要 --enable-core-pgsql-support 参数，编译前需要 make clean 一下）
chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure && make -j`nproc` && make install
# chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure --enable-core-pgsql-support && make -j`nproc` && make install
# chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure --enable_core_pgsql-pkgconfig && make -j`nproc` && make install
mv /usr/local/freeswitch/conf /usr/local/freeswitch/.conf
# copy phone music and sounds to fs dir files
cp -R sounds /usr/local/freeswitch/sounds


# 增加软连接
ln -sf /usr/local/freeswitch/bin/freeswitch /usr/bin/ \
    && ln -sf /usr/local/freeswitch/bin/fs_cli /usr/bin/

# 设置时区
ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone
apt-get update && apt-get install -y locales && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8