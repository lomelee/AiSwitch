#!/bin/sh
#设置sources镜像（本机设置了清华大学镜像）
# sed -i s/deb.debian.org/mirrors.aliyun.com/g /etc/apt/sources.list 
apt-get update && apt-get -yq install git-core wget

git clone https://github.com/lomelee/AiSwitch /usr/src/AiSwitch
git clone https://github.com/signalwire/libks /usr/src/libs/libks
git clone https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp

# add build tool depend
apt-get update && apt-get -yq install --no-install-recommends build-essential cmake automake autoconf 'libtool-bin|libtool' pkg-config

# add runtime depend
apt-get update && apt-get -yq install --no-install-recommends \
libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison libtpl-dev libtiff5-dev uuid-dev \
libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
libogg-dev libspeex-dev libspeexdsp-dev \
libldns-dev \
libavformat-dev libswscale-dev libavresample-dev \
liblua5.2-dev \
libopus-dev \
# mysql 或者 mariadb 模块编译依赖
libmariadb-dev \
# PgSQL 模块编译依赖
# libpq-dev \
libsndfile1-dev libflac-dev libogg-dev libvorbis-dev \
libshout3-dev libmpg123-dev libmp3lame-dev \
# conference 会议中需要
libpng-dev 


# build from source 
cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install 
cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr/local && make -j`nproc --all` && make install
cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
# 编译前可以 make clean 一下， 获取直接 git clean -xfd 清空非版本控制的数据
chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure && make -j`nproc` && make install
# mysql 或者 mariadb 也不需要 添加 --enable-core-odbc-support 参数支持
# chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure --enable-core-odbc-support && make -j`nproc` && make install
# 添加pgsql驱动套件编译选项（PgSQL 不在需要 --enable-core-pgsql-support  参数，编译前需要 make clean 一下）
# chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure --enable-core-pgsql-support && make -j`nproc` && make install
# chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure --enable_core_pgsql-pkgconfig && make -j`nproc` && make install

# 拉取mod_unimrcp 依赖项
wget https://www.unimrcp.org/project/component-view/unimrcp-deps-1-6-0-tar-gz/download -O /usr/src/libs/unimrcp-deps-1.6.0.tar.gz
# git clone -b unimrcp-1.8.0 https://github.com/unispeech/unimrcp.git /usr/src/libs/unimrcp
git clone https://github.com/lomelee/unimrcp.git /usr/src/libs/unimrcp
git clone https://github.com/lomelee/mod_unimrcp.git /usr/src/libs/mod_unimrcp
# unimrcp 依赖项编译
cd /usr/src/libs && tar -xvzf unimrcp-deps-1.6.0.tar.gz
cd /usr/src/libs/unimrcp-deps-1.6.0/libs/apr && ./configure --prefix=/usr/local/apr && make && make install
# 如果编译后docker 无法运行或加载 mod_unimrcp 模块，那么设置安装目录到 /usr/lib下面 --prefix=/usr
cd /usr/src/libs/unimrcp-deps-1.6.0/libs/apr-util && ./configure --with-apr=/usr/src/libs/unimrcp-deps-1.6.0/libs/apr --prefix=/usr/local/apr && make && make install
# 如果编译后docker 无法运行或加载 mod_unimrcp 模块，那么设置安装目录到 /usr/lib下面 --prefix=/usr
cd /usr/src/libs/unimrcp && ./bootstrap && ./configure --disable-client-app --disable-umc --disable-asr-client --disable-server-app --disable-server-lib --disable-demosynth-plugin --disable-demorecog-plugin --disable-demoverifier-plugin --disable-recorder-plugin --with-sofia-sip=/usr && make && make install
# 设置 PKG_CONFIG_PATH，为编译 mod_unimrcp 模块准备（临时设置包搜索路径，在生效在当前shell session 中）
# 编译 mod_unimrcp 模块
export PKG_CONFIG_PATH=/usr/local/freeswitch/lib/pkgconfig:/usr/local/unimrcp/lib/pkgconfig && cd /usr/src/libs/mod_unimrcp && ./bootstrap.sh && ./configure && make && make install

# 移动配置
mv /usr/local/freeswitch/conf /usr/local/freeswitch/.conf
# 进入编译目录
cd /usr/src/AiSwitch
# copy phone music and sounds to fs dir files
cp -R sounds /usr/local/freeswitch/sounds


# 增加软连接
ln -sf /usr/local/freeswitch/bin/freeswitch /usr/bin/ \
    && ln -sf /usr/local/freeswitch/bin/fs_cli /usr/bin/

# 设置时区
ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone
apt-get update && apt-get install -y locales && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8