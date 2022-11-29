### Alpine 3.16
### PHP Version 8.1.13
### COMPOSER Version 2.3.10

#### 簡介:
最小安裝 php 運作，僅安裝 COMPOSER 無其他非必要套件


#### 使用方式
直接建立 images
```
docker build -t name .
```
同時可結合 docker-compose

```
version: '3.1'
services:
  php1:
    build: ./
    ports:
      - "9000:9000"
    volumes:
      - ./:/www/:rw
    restart: always
    cap_add:
      - SYS_PTRACE
  php2:
    build: ./
    ports:
      - "9000:9000"
    volumes:
      - ./:/www/:rw
    restart: always
    cap_add:
      - SYS_PTRACE

  nginx:
    image: nginx
    ports:
      - "80:80"
      - "443:443"
    links:
      - php1
      - php2
    restart: always
```

#### 已安裝 PHP Modules :

```
[PHP Modules]
bcmath
Core
ctype
curl
date
dom
fileinfo
filter
ftp
gd
hash
iconv
intl
json
libxml
mbstring
mysqli
mysqlnd
openssl
pcre
PDO
pdo_mysql
pdo_sqlite
Phar
posix
readline
Reflection
session
SimpleXML
sodium
SPL
sqlite3
standard
tokenizer
xml
xmlreader
xmlwriter
Zend OPcache
zip
zlib

[Zend Modules]
Zend OPcache
```