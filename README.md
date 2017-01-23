# maidea_webserver
Nginx, Php-fpm and wkhtml container for simple docker dev/test environments
- for use with CakePhp


TODO: propper readme

####Version 1:
nginx root is set to */src/app/webroot*

using compose:
```yaml
webserver:
  image: panter4/maidea_webserver:1
  volumes:
   - "./src:/src"
  environment:
    #for use witn jwilder/nginx-proxy
   - VIRTUAL_HOST=host.example.com
  expose:
   - "80"
  container_name: webserver1
  ```


####Version 2:

nginx root is set to */app/webroot*

using compose:
```yaml
webserver:
  image: panter4/maidea_webserver:2
  volumes:
   - "./src/app:/app"
  environment:
    #for use witn jwilder/nginx-proxy
   - VIRTUAL_HOST=host.example.com
  expose:
   - "80"
  container_name: webserver1
  ```

