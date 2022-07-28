FROM debian:bullseye AS FirstBuildStep
LABEL Author="Allen lee"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -yq install git-core

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
    # mod_pgsql
    libpq-dev \
    # mod_sndfile
    libsndfile1-dev libflac-dev libogg-dev libvorbis-dev \
    # mod_shout(mp3)
    libshout3-dev libmpg123-dev libmp3lame-dev 


# build from source 
RUN cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install 
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
# 添加pgsql驱动套件编译选项
RUN chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure && make -j`nproc` && make install
# RUN chmod -R +x /usr/src/AiSwitch && cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure --enable_core_pgsql_pkgconfig && make -j`nproc` && make install
RUN mv /usr/local/freeswitch/conf /usr/local/freeswitch/.conf
# copy phone music and sounds to fs dir files
COPY sounds /usr/local/freeswitch/sounds