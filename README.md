# Maidea web server
Nginx/Apache, php-fpm and wkhtml container for simple docker dev/test environments
* intended for use with CakePhp, but works with any compatible php configuration
* dev branch has xdebug

#### Dev images:

* Based on the official **[php+apache](https://hub.docker.com/r/library/php/)** images
* **Apache** root is set to */src/app/webroot*
* **XDebug** (2.5.5) is enabled and configured to connect to remote client
    * To make XDebug connect to the dev machine, set the **XDEBUG_REMOTE_HOST** environment variable to your dev IP address (xdebug.remote_host config)
    * You can set the xdebug.idekey via the **XDEBUG_IDE_KEY** environment variable (e.g. XDEBUG_IDE_KEY=PHPSTORM)
* **wkhtmltopdf** (0.12.4) binary added to /usr/local/bin

Tags:

* **dev** - the default dev image
    * php5.6
* Specific image tags:
    * **dev-apache-php5.6**
    * **dev-apache-php7.2**

The recommended development configuration is using **[Docker Compose](https://docs.docker.com/compose/)**:
```yaml
version: '3'

services:
  my_webapp:
  
    image: maidea/webserver:dev
    
    volumes:
      # docker volume for app source
      - "./src:/src"
      
    environment:
      # uncomment and modify the next two lines if using jwilder/nginx-proxy
      #- VIRTUAL_PORT=80
      #- VIRTUAL_HOST=host.example.com
      
    # uncomment and modify the next two lines if using traefik
    #labels:
      #- "traefik.frontend.rule=Host:host.example.com"
      
    expose:
      - "80"
    
    # example connection to development microservices:
    external_links:
      - mailhog
      
    # use whichever network config you require, e.g.:
    network_mode: "bridge"
  ```

---

##### [DEPRECATED] Version 1:
nginx root is set to */src/app/webroot*

using compose:
```yaml
webserver:
  image: maidea/webserver:1
  volumes:
   - "./src:/src"
  environment:
    #for use witn jwilder/nginx-proxy
   - VIRTUAL_HOST=host.example.com
  expose:
   - "80"
  container_name: webserver1
  ```


##### [DEPRECATED] Version 2:

nginx root is set to */app/webroot*

using compose:
```yaml
webserver:
  image: maidea/webserver:2
  volumes:
   - "./src/app:/app"
  environment:
    #for use witn jwilder/nginx-proxy
   - VIRTUAL_HOST=host.example.com
  expose:
   - "80"
  container_name: webserver1
  ```
