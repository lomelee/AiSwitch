#!/bin/sh
# 删除以前的版本
rm /usr/local/freeswitch -rf
# 清空以前的编译构建数据
git clean -xfd
# 编译前可以 make clean 一下， 获取直接 git clean -xfd 清空非版本控制的数据
cd /usr/src/AiSwitch && ./bootstrap.sh -j && ./configure && make -j`nproc` && make install

# 设置 PKG_CONFIG_PATH，为编译 mod_unimrcp 模块准备（临时设置包搜索路径，在生效在当前shell session 中）
export PKG_CONFIG_PATH=/usr/local/freeswitch/lib/pkgconfig:/usr/local/unimrcp/lib/pkgconfig
# 编译 mod_unimrcp 模块
cd /usr/src/libs/mod_unimrcp && ./bootstrap.sh && ./configure && make && make install
# 移动配置
# mv /usr/local/freeswitch/conf /usr/local/freeswitch/.conf
# copy phone music and sounds to fs dir files
# cp -R /usr/src/AiSwitch/sounds /usr/local/freeswitch/sounds

# 删除默认配置
rm /usr/local/freeswitch/conf -rf
# 添加软链接
ln -sf /usr/src/AiSwitch/aisConf /usr/local/freeswitch/conf
ln -sf /usr/src/AiSwitch/sounds /usr/local/freeswitch/sounds


# 增加软连接
# ln -sf /usr/local/freeswitch/bin/freeswitch /usr/bin/ && ln -sf /usr/local/freeswitch/bin/fs_cli /usr/bin/

# 设置时区
# ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone
# apt-get update && apt-get install -y locales && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8