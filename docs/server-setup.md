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
