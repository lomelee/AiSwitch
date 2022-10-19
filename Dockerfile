FROM debian:bullseye AS FirstBuildStep
LABEL Author="Allen lee"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -yq install git-core wget

RUN git clone https://github.com/lomelee/AiSwitch /usr/src/AiSwitch
RUN git clone https://github.com/signalwire/libks /usr/src/libs/libks
RUN git clone https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
RUN git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp

# add build tool depend
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -yq install --no-install-recommends \
    # build
    build-essential cmake automake autoconf 'libtool-bin|libtool' pkg-config

# add runtime depend
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -yq install --no-install-recommends \
    # general # erlang-dev
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison  libtpl-dev libtiff5-dev uuid-dev \
    # core
    libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
    # core codecs
    libogg-dev libspeex-dev libspeexdsp-dev \
    # mod_enum
    libldns-dev \
    # mod_python3
    # python3-dev \
    # mod_av
    libavformat-dev libswscale-dev libavresample-dev \
    # mod_lua
    liblua5.2-dev \
    # mod_opus
    libopus-dev \
    # mod_mariadb (mariadb 和 mysql)
    libmariadb-dev \
    # mod_pgsql (postgreSQL)
    # libpq-dev \
    # mod_sndfile
    libsndfile1-dev libflac-dev libogg-dev libvorbis-dev \
    # mod_shout(mp3)
    libshout3-dev libmpg123-dev libmp3lame-dev 


# build from source 
RUN cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install 
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
# 编译 freeswitch
RUN chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure && make -j`nproc` && make install

# 拉取mod_unimrcp 依赖项
RUN wget https://www.unimrcp.org/project/component-view/unimrcp-deps-1-6-0-tar-gz/download -O /usr/src/libs/unimrcp-deps-1.6.0.tar.gz
# git clone -b unimrcp-1.7.0 https://github.com/unispeech/unimrcp.git /usr/src/libs/unimrcp
RUN git clone https://github.com/unispeech/unimrcp.git /usr/src/libs/unimrcp
RUN git clone https://github.com/freeswitch/mod_unimrcp.git /usr/src/libs/mod_unimrcp
# unimrcp 依赖项编译
RUN cd /usr/src/libs
RUN tar xvzf unimrcp-deps-1.6.0.tar.gz
RUN cd /usr/src/libs/unimrcp-deps-1.6.0/libs/apr && ./configure --prefix=/usr/local/apr && make && make install
# 如果编译后docker 无法运行或加载 mod_unimrcp 模块，那么设置安装目录到 /usr/lib下面 --prefix=/usr
RUN cd /usr/src/libs/unimrcp-deps-1.6.0/libs/apr-util && ./configure --with-apr=/usr/src/libs/unimrcp-deps-1.6.0/libs/apr --prefix=/usr/local/apr && make && make install
# 如果编译后docker 无法运行或加载 mod_unimrcp 模块，那么设置安装目录到 /usr/lib下面 --prefix=/usr
RUN cd /usr/src/libs/unimrcp && ./bootstrap && ./configure --disable-client-app --disable-umc --disable-asr-client --disable-server-app --disable-server-lib --disable-demosynth-plugin --disable-demorecog-plugin --disable-demoverifier-plugin --disable-recorder-plugin --with-sofia-sip=/usr && make && make install
# 设置 PKG_CONFIG_PATH，为编译 mod_unimrcp 模块准备（临时设置包搜索路径，在生效在当前shell session 中）
RUN export PKG_CONFIG_PATH=/usr/local/freeswitch/lib/pkgconfig:/usr/local/unimrcp/lib/pkgconfig
# 编译 mod_unimrcp 模块
RUN cd /usr/src/libs/mod_unimrcp && ./bootstrap.sh && ./configure && make && make install


# 移动配置信息文件夹
RUN mv /usr/local/freeswitch/conf /usr/local/freeswitch/.conf
# copy phone music and sounds to fs dir files
COPY sounds /usr/local/freeswitch/sounds