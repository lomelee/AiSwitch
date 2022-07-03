# Freeswitch添加中文语音

# 从Xswitch docker 镜像中找到 安装目录，

```
make bash

cd /usr/local/freeswitch/sounds/zh/cn

```

# 从容器中拷贝资源文件到宿主机
docker cp xswitch:/usr/local/freeswitch/sounds/zh/cn  /mnt/

# 开始修改fs的配置文件

vim /usr/local/freeswitch/conf/vars.xml

```
  <X-PRE-PROCESS cmd="set" data="sound_prefix=$${sounds_dir}/zh/cn/sinmei/"/>
  <X-PRE-PROCESS cmd="set" data="default_language=zh"/>
  <X-PRE-PROCESS cmd="set" data="default_dialect=cn"/>
  <X-PRE-PROCESS cmd="set" data="default_voice=sinmei"/>
  
```


# 复制修改中文SAY配置

cd /usr/local/freeswitch/conf/lang/
cp -fr en zh
cd zh
mv en.xml cn.xml

# 修改 cn.xml

```
<language name="zh" say-module="en" sound-prefix="$${sounds_dir}/zh/cn/sinmei" tts-engine="cepstral" tts-voice="sinmei">

```

# conf/freeswitch.xml 添加中文配置入口

```
<X-PRE-PROCESS cmd="include" data="lang/zh/*.xml"/>

```

# 如果安装了ZH SAY模块，就进行配置, 打开自动加载中文模块的配置

```
<load module="mod_say_zh"/>

```