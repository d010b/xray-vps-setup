# xray-vps-setup
VLESS с доменом. XHttp?   MARZBAN не полностью совместимая панель c xhttp - генерирует в конфигурации мусорные XHTTP Extra несовместимые с некоторыми популярными клиентами. При использовании Marzban нужно подбирать клиента.

Изменения в сравнении с оригинальным скриптом:
- - Xhttp почти работает
- - Защита бесполезной www страницы паролем от ботов и анализа.
- - Минимальная защита от сканеров.
- - Геофайлы адаптированные для России(например whitelist), плюс значительно уменьшенного размера за счет чисто китайских позиций.
- - Возможны ошибки и бесполезный код.

В данном варианте VLESS слушает на 443 и принимате все запросы, делая запрос на локальный Angie(форк nginx) только для сертификатов. В таком варианте задержка будет меньше, чем в варианте с Caddy/NGINX перед VLESS, где происходит множество лишних запросов. 
## Скрипт

- Установит Xray/Marzban на ваш выбор. Для маскировки страницы используется [Conflunce](https://github.com/Jolymmiles/confluence-marzban-home)
- На ваше усмотрение настроит:
- - Iptables, запретив все подключения, кроме SSH, 80 и 443.
- - Создаст пользователя для подключения, запретив вход от рута
- - Добавит этому пользователю ключ для SSH, запретив вход по паролю
- - Настроит WARP для ру-сайтов.  
```bash
tmux
bash <(wget -qO- https://raw.githubusercontent.com/d010b/xray-vps-setup/main/vps-setup.sh)
```

## Плейбук

[Ansible-galaxy](https://galaxy.ansible.com/ui/standalone/roles/Akiyamov/xray-vps-setup/install/)
```yaml
- name: Setup vps 
  hosts: some_host
  roles:
    - Akiyamov.xray-vps-setup  
  vars:
    domain: example.com # домен, уровень неважен
    setup_variant: marzban # marzban or xray
    setup_warp: false # true or false
```

## Добавляем подписку и поддержку Mihomo

```
bash <(wget -qO- https://github.com/legiz-ru/marz-sub/raw/main/marz-sub.sh)
```
После этого сделайте `docker compose -f /opt/xray-vps-setup/docker-compose.yml down && docker compose -f /opt/xray-vps-setup/docker-compose.yml up -d` 


## Ручная установка

Описана [здесь](https://github.com/Akiyamov/xray-vps-setup/blob/main/install_in_docker.md).  

<strike>Caddy</strike> Angie сам получит сертификаты, поэтому нам не придется их получать через `acme.sh` или `certbot`.  
Sing-box - да, не очень.  
XHTTP позже, а больше не надо. Уже точно. 

## Связь
Issues, PR ну или мой [тг](https://t.me/Akiyamov).
