# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

Виртуальная машина создана в Oracle VirtualBox.

Основные параметры:

- имя виртуальной машины: devops-vm;
- операционная система: Ubuntu Server 24.04.5 LTS;
- оперативная память: 2048 МБ;
- количество процессоров: 2;
- размер виртуального диска: 25 ГБ.

## 2. Сетевые интерфейсы

Для виртуальной машины настроено два сетевых адаптера.

### Адаптер 1

Тип подключения: NAT.

Полученный IP-адрес:

```text
10.0.2.15
```

## 8. Веб-сервер

На сервере установлен Nginx.

Конфигурация ресурса:
/etc/nginx/sites-available/devops-site

Активная конфигурация:
/etc/nginx/sites-enabled/devops-site

Каталог сайта:
/var/www/devops-site

Владелец файлов:
devops:devops

Права доступа:
- каталоги — 755;
- файлы — 644.

TLS-сертификат:
/etc/ssl/certs/devops.crt

Закрытый ключ:
/etc/ssl/private/devops.key

Права сертификата — 644.
Права закрытого ключа — 600.

Сертификат создан для имени devops.local и содержит SAN DNS:devops.local.
Срок действия сертификата — 365 дней.

HTTP на порту 80 перенаправляется на HTTPS.
HTTPS обслуживается на порту 443.

Доставка файлов сайта выполняется с помощью rsync и scripts/deploy.sh.

## 9. Контейнеризация

Docker Engine Community 29.9.2 установлен из официального APT-репозитория https://download.docker.com/linux/ubuntu для Ubuntu 24.04 (noble). Установлены docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin и docker-compose-plugin. Версия Docker Compose — 5.6.1. Служба docker включена в автозагрузку.

Пользователь devops добавлен в группу docker; после нового SSH-подключения команды Docker выполняются без sudo. Участие в этой группе фактически предоставляет привилегии root, поэтому доступ ограничен административной учётной записью devops.

Исходники находятся в каталоге app репозитория devops-course-2026 на Windows. На сервере проект размещён в /home/devops/app. Доставка выполняется из WSL командой rsync -avz --exclude=.env --chmod=D755,F644 app/ devops:app/; перед доставкой используется --dry-run. Файл .env исключён из синхронизации, Git и контекста сборки. Шаблон переменных — app/.env.example.

Файл /home/devops/app/.env создаётся только на сервере, принадлежит devops и имеет права 600. Он содержит POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD и DB_HOST. Пароль генерируется командой openssl rand -hex 16; фактическое значение не включается в документацию и репозиторий.

Образ приложения devops-app:1.0 собирается из python:3.12-slim, зависимости устанавливаются из requirements.txt. Gunicorn слушает 0.0.0.0:5000 внутри контейнера и работает от непривилегированного пользователя app. Проект запускается командой cd /home/devops/app && docker compose up -d --build.

Compose-сервис db использует postgres:16-alpine. PostgreSQL проверяется через pg_isready; приложение запускается после достижения состояния service_healthy. Сервисы находятся в сети app_backend типа bridge; имя db разрешается встроенным DNS Docker. Порт приложения опубликован только как 127.0.0.1:5000:5000. Порт 5432 базы данных на хосте не публикуется.

Данные PostgreSQL хранятся в именованном томе app_db_data, подключённом к /var/lib/postgresql/data. docker compose down сохраняет этот том. docker compose down -v удаляет том и данные; в работе команда применялась только к учебному проекту после резервного копирования pg_dump. Резервная копия сохранена на сервере в /home/devops/pr7-before-volume-reset.sql с правами 600.

В HTTPS-блок /etc/nginx/sites-available/devops-site добавлена конфигурация:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Перед применением выполняются sudo nginx -t и sudo systemctl reload nginx. Конечный слеш в proxy_pass заменяет префикс /app/ на /. Приложение доступно по https://devops.local/app/, проверка состояния — по https://devops.local/app/health. Статический сайт по https://devops.local/ продолжает работать. Доверие к самоподписанному сертификату на хосте задаётся через curl --cacert ~/devops.crt.

Журнал ошибок Nginx: /var/log/nginx/devops-site.error.log. При остановленном app запрос к /app/ возвращает 502; в журнале появляется connect() failed (111: Connection refused) while connecting to upstream. После docker compose start app проверка /app/health снова возвращает ok.

В scripts/audit.sh добавлен раздел [5] Контейнеризация: состояние docker, healthy у app-db-1, отсутствие внешней публикации портов 5000 и 5432, права .env 600. Сценарий использует sudo для проверок SSH, UFW и TLS-ключа из предыдущей работы. Запуск: bash ~/audit.sh. Для отрицательного теста публикация приложения временно меняется на 5000:5000; после теста обязательно восстанавливается 127.0.0.1:5000:5000.


## 10. Управление конфигурацией через Ansible

Практика 11 выполнена на чистом снимке `01-clean-install`. Предыдущее состояние сохранено в снимке `08-before-practice11`; разделы 8 и 9 выше описывают прежнюю конфигурацию. В текущем стенде Nginx обслуживает HTTP на порту 80, TLS и PostgreSQL не разворачиваются.

Управляющий узел — Ubuntu в WSL, проект `/home/user/devops-course-2026/ansible`. Управляемый узел — Ubuntu Server 24.04 в VirtualBox, Host-only `192.168.56.102:22`. Адрес зависит от локальной сети; перед запуском его нужно проверить и при необходимости изменить в inventory.

`inventory/bootstrap.ini` использует пользователя `student` с интерактивным вводом SSH- и sudo-пароля. `inventory/prod.ini` использует `devops` и ключ `~/.ssh/devops_vm`. Закрытый ключ и пароли не хранятся в репозитории. Открытый ключ читается с управляющего узла из `~/.ssh/devops_vm.pub`. Проверка ключа хоста включена; известный ключ VM должен быть проверен по доверенному отпечатку до bootstrap.

Роли в `site.yml` выполняются последовательно:

- `base`: проверка Ubuntu 24.04 amd64, пакеты `python3-debian` и `python3-requests`, официальный Docker APT-репозиторий через `deb822_repository`, установка и автозапуск Docker;
- `ssh`: пользователь devops, открытый ключ, sudoers с проверкой visudo, запрет root/password SSH после установки ключа, UFW с разрешёнными 22/tcp и 80/tcp;
- `nginx`: шаблон reverse proxy, отключение default site, symlink, проверка `nginx -t` перед reload;
- `app`: загрузка выбранного образа, запуск контейнера и проверка `/health`.

Параметры в `group_vars/all.yml`:

```yaml
app_image: ghcr.io/muzraev/devops-ci-app
app_tag: aa798123d0404526280cc3f6de9ea0bc60eaddca
app_container_name: devops-ci-app
app_host_port: 5000
app_internal_port: 5000
```

Образ публичный; используется анонимное чтение GHCR. На VM приложение не пересобирается. Контейнер публикует порт только как `127.0.0.1:5000:5000`; Nginx принимает внешние запросы на 80 и проксирует к loopback. Проверка с управляющего узла: `curl --noproxy '*' -i http://192.168.56.102/health`. Ожидаются HTTP 200 и JSON `{"status":"ok"}`.

В `ansible.cfg` включены `host_key_checking = True`, `force_handlers = True` и SSH pipelining. Коллекции закреплены в `requirements.yml`: ansible.posix 1.6.2, community.docker 4.5.0, community.general 9.5.0. Docker-модулю задан timeout 180 секунд после первоначального таймаута API при создании контейнера.

Команды из каталога `ansible/`:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/prod.ini --graph
ansible-playbook -i inventory/bootstrap.ini site.yml --syntax-check
ansible-playbook -i inventory/prod.ini site.yml --syntax-check
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
ansible vm -m ansible.builtin.ping
ansible-playbook -i inventory/prod.ini site.yml
ansible-playbook -i inventory/prod.ini verify.yml
```

Последующие запуски выполняются по ключу без паролей. `NOPASSWD:ALL` и участие devops в группе docker дают административные привилегии; ключ используется только для учебного администрирования VM.

Проверки выполнены 24.11.2026:

- повторный `site.yml`: `ok=24 changed=0 failed=0`;
- drift: удалён контейнер, upstream Nginx изменён на 5001, получен HTTP 502; один `site.yml` восстановил шаблон и контейнер (`ok=26 changed=3 failed=0`), после handlers получен HTTP 200;
- неверный тег из 40 нулей передан через `-e app_tag=0000000000000000000000000000000000000000`; pull завершился 404 до задачи контейнера (`ok=21 changed=0 failed=1`), ID существующего контейнера не изменился, HTTP остался 200;
- запуск с рабочим тегом снова дал `ok=24 changed=0 failed=0`;
- `verify.yml` дважды дал `ok=6 changed=0 failed=0`; аудит читает effective sshd config, Docker container info и health через Nginx;
- при остановленном контейнере аудит обнаружил `State.Running=false` (`ok=3 changed=0 failed=1`) и не запустил контейнер; восстановление через `site.yml` дало `ok=24 changed=1 failed=0`, затем аудит и HTTP снова успешны.

Во время работы отдельно наблюдался kernel watchdog soft lockup в VM. После перезапуска VM SSH и приложение восстановились автоматически; проверка неверного тега была повторена на доступном узле. Этот сбой не считается результатом теста ошибочного тега.

Для будущего запуска из GitHub Actions нужен сетевой путь к VM: облачный GitHub-hosted runner не достигает Host-only адреса. Варианты — туннель, облачная VM либо self-hosted runner с отдельной защитой и приватным репозиторием. Ключ деплоя и проверенный known_hosts передаются через Secrets без вывода в журнал. В этой работе runner и Secrets не настраивались.
