FROM debian:bullseye AS FirstBuildStep
LABEL Author="Allen lee"

# 修改debian镜像源
# RUN sed -i s/deb.debian.org/mirrors.aliyun.com/g /etc/apt/sources.list 
# 安装工具包
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -yq install git-core wget 

# 获取需要编译的依赖项目源码
RUN git clone https://github.com/lomelee/AiSwitch /usr/src/AiSwitch
#RUN git clone https://github.com/signalwire/libks /usr/src/libs/libks
#RUN git clone https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
#RUN git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp
RUN git clone --branch v1.8.3 https://github.com/signalwire/libks.git /usr/src/libs/libks
RUN git clone --branch v1.13.15 https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
RUN git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp
# 728b60abdd1a71e254b8e831e9156521d788b2b9
RUN cd /usr/src/libs/spandsp && git checkout 728b60abdd1a71e254b8e831e9156521d788b2b9
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
    libshout3-dev libmpg123-dev libmp3lame-dev \
    # conference 会议中需要
    libpng-dev 


# build from source 
RUN cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install 
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
# 编译 freeswitch
RUN chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure && make -j`nproc` && make install

# 拉取 mod_unimrcp 依赖项
RUN wget https://www.unimrcp.org/project/component-view/unimrcp-deps-1-6-0-tar-gz/download -O /usr/src/libs/unimrcp-deps-1.6.0.tar.gz
# git clone -b unimrcp-1.8.0 https://github.com/unispeech/unimrcp.git /usr/src/libs/unimrcp
RUN git clone https://github.com/lomelee/unimrcp.git /usr/src/libs/unimrcp
RUN git clone https://github.com/lomelee/mod_unimrcp.git /usr/src/libs/mod_unimrcp
# unimrcp 依赖项编译
RUN cd /usr/src/libs && tar -zxvf unimrcp-deps-1.6.0.tar.gz
RUN cd /usr/src/libs/unimrcp-deps-1.6.0/libs/apr && ./configure --prefix=/usr/local/apr && make && make install
# 如果编译后docker 无法运行或加载 mod_unimrcp 模块，那么设置安装目录到 /usr/lib下面 --prefix=/usr
RUN cd /usr/src/libs/unimrcp-deps-1.6.0/libs/apr-util && ./configure --with-apr=/usr/src/libs/unimrcp-deps-1.6.0/libs/apr --prefix=/usr/local/apr && make && make install
# 如果编译后docker 无法运行或加载 mod_unimrcp 模块，那么设置安装目录到 /usr/lib下面 --prefix=/usr
RUN cd /usr/src/libs/unimrcp && ./bootstrap && ./configure --disable-client-app --disable-umc --disable-asr-client --disable-server-app --disable-server-lib --disable-demosynth-plugin --disable-demorecog-plugin --disable-demoverifier-plugin --disable-recorder-plugin --with-sofia-sip=/usr && make && make install
# 设置 PKG_CONFIG_PATH，为编译 mod_unimrcp 模块准备（临时设置包搜索路径，在生效在当前shell session 中）
# 编译 mod_unimrcp 模块
RUN export PKG_CONFIG_PATH=/usr/local/freeswitch/lib/pkgconfig:/usr/local/unimrcp/lib/pkgconfig && cd /usr/src/libs/mod_unimrcp && ./bootstrap.sh && ./configure && make && make install

# 移动默认配置信息到隐藏的.conf文件夹
RUN mv /usr/local/freeswitch/conf /usr/local/freeswitch/.conf

# 拷贝相关文件到运行目录(docker中没有 cp -r 命令选项，因为他类似于 unix) 
# 注意：docker 中 copy 源文件夹必须是当前目录，所以先 cd 到指定目录
RUN cd /usr/src/AiSwitch
COPY aisConf /usr/local/freeswitch/conf
COPY sounds /usr/local/freeswitch/sounds
COPY aisScript /usr/local/freeswitch/scripts
COPY aisGrammar /usr/local/freeswitch/grammar

COPY aisConf /usr/local/freeswitch/.aisConf
COPY sounds usr/local/freeswitch/.sounds
COPY aisScript /usr/local/freeswitch/.scripts
COPY aisGrammar /usr/local/freeswitch/.grammar
