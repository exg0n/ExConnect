# ExConnect

Клиент прокси для OpenWrt 25.12.5 с управлением из LuCI. Версия `0.1.0` находится в разработке.

## Что реализовано

- Импорт ссылок VLESS, VMess, Shadowsocks, Trojan, Hysteria2, SOCKS и HTTP. В одном экземпляре выбирается один исходящий профиль.
- Подписки по HTTPS с ручным обновлением. Поддерживаются списки ссылок в обычном тексте и Base64.
- SOCKS и HTTP на самом роутере. Для клиентов LAN доступен прозрачный режим на nftables TPROXY с выбранными интерфейсами.
- Маршрутизация по доменам и IP-адресам. Правила могут направлять трафик через профиль, напрямую или блокировать его.
- Пользовательские `geoip.dat` и `geosite.dat` по HTTPS с готовыми адресами RunetFreedom. Для произвольного имени файла используется синтаксис Xray `ext:<имя.dat>:<тег>`.
- Управление профилями, подписками, правилами и службой в LuCI. Русский и английский интерфейс используют выбранный язык LuCI.

## Установка на роутер

Понадобятся OpenWrt **25.12.5**, доступ по SSH под `root`, свободное место для Xray и доступ с роутера к GitHub и репозиториям OpenWrt. Проверьте версию и свободное место на роутере:

```sh
ubus call system board
df -h /overlay /tmp
```

### Автоматическое скачивание и установка

Откройте [GitHub Actions](https://github.com/exg0n/ExConnect/actions/workflows/openwrt.yml) и убедитесь, что у успешной сборки ветки `main`, запущенной после отправки коммита, есть архив `exconnect-openwrt-25.12.5-x86-64` в разделе **Artifacts**. GitHub хранит такие архивы ограниченное время. Автоматическая сборка использует SDK `x86/64`. Для другой цели можно собрать пакеты вручную по инструкции ниже.

Репозиторий приватный. Создайте [fine-grained токен GitHub](https://github.com/settings/personal-access-tokens/new) с доступом только к `ExConnect` и правами **Contents → Read-only** и **Actions → Read-only**. Команда запросит токен и скроет его при вводе.

Подключитесь по SSH к роутеру, например `ssh root@192.168.1.1`. Выполните в оболочке роутера одну строку:

```sh
(set -eu; grep -qx "DISTRIB_RELEASE='25.12.5'" /etc/openwrt_release; apk update; apk add ca-bundle curl jsonfilter unzip; printf 'GitHub token: '; IFS= read -rs token; printf '\n'; test -n "$token"; installer=$(mktemp /tmp/exconnect-installer.XXXXXX); trap 'rm -f "$installer"' EXIT; printf 'Authorization: Bearer %s\n' "$token" | curl -q -fsS --proto '=https' -H @- -H 'Accept: application/vnd.github.raw+json' -o "$installer" 'https://api.github.com/repos/exg0n/ExConnect/contents/scripts/install-openwrt.sh?ref=main'; printf '%s\n' "$token" | sh "$installer")
```

Команда скачает установщик из `main`, возьмёт два `.apk` из последней успешной сборки этой ветки и установит их. `apk` скачает Xray и остальные зависимости из настроенных репозиториев OpenWrt. По окончании откройте **Службы → ExConnect** в LuCI.

### Ручная сборка и установка

На Linux распакуйте официальный [SDK OpenWrt 25.12.5](https://downloads.openwrt.org/releases/25.12.5/targets/) для цели роутера. Сверьте SHA-256 архива с опубликованной контрольной суммой.

```sh
bash scripts/build-openwrt.sh /path/to/openwrt-sdk
```

Скрипт сохранит `exconnect` и `luci-app-exconnect` в `dist/`. Готовые пакеты можно также скачать из **Artifacts** на странице успешной сборки GitHub Actions и распаковать на компьютере. Скопируйте оба `.apk` в `/tmp/exconnect/` на роутере. Выполните по SSH под `root`:

```sh
cd /tmp/exconnect && apk update && apk add --allow-untrusted ./exconnect-[0-9]*.apk ./luci-app-exconnect-[0-9]*.apk
```

Флаг `--allow-untrusted` нужен для установки локальных пакетов без подписи. Если LuCI уже открыт, обновите страницу после установки.

## Первое подключение

1. Откройте **Службы → ExConnect** в LuCI.
2. Добавьте ссылку в **Профилях** или сохраните URL в **Подписках** и нажмите **Обновить профили**.
3. В **Настройках** выберите профиль и режим, включите службу и сохраните параметры. В **Обзоре** проверьте конфигурацию и примените её к службе.
4. Для прозрачного режима укажите интерфейс клиентской сети, например `br-lan`. Настройку проверяйте на тестовой сети, где доступ к роутеру легко восстановить.
5. Для списков `.dat` добавьте HTTPS-источник в **Файлах правил**, сохраните его и загрузите. Добавьте соответствующие доменные или IP-условия в правила маршрутизации и снова примените конфигурацию службы.

Для Hysteria2 подходит TLS-сертификат от доверенного центра. Для собственного сертификата укажите `pinSHA256` в ссылке. См. [документацию Hysteria в Xray](https://xtls.github.io/en/config/outbounds/hysteria.html) и [документацию маршрутизации Xray](https://xtls.github.io/en/config/routing.html).

Для диагностики проверьте пакеты и журнал роутера:

```sh
apk info -e exconnect luci-app-exconnect xray-core
/etc/init.d/exconnect status
logread -e exconnect
```

## Проверки и статус

```sh
node --test tests/source.test.cjs
```

Порядок проверки с Xray, `ucode` и UCI описан в [tests/README.md](tests/README.md). Для приёмки необходимы сборка `.apk` и проверка на OpenWrt с реальным Hysteria2-сервером, трафиком LAN и переключением правил. Полное соответствие v2rayA требует отдельных функций, включая группы серверов, балансировку, расширенные настройки DNS и импорт через QR-код. Загрузка локальных `.dat` из браузера также остаётся в плане. На этапе применения правил Xray проверяет файлы и теги, на которые ссылается конфигурация.

Проекты, с которыми сверялся ExConnect: [v2raya-openwrt](https://github.com/v2rayA/v2raya-openwrt), [v2rayA](https://github.com/v2rayA/v2rayA), [Podkop](https://github.com/itdoginfo/podkop) и [RunetFreedom](https://github.com/runetfreedom/russia-v2ray-rules-dat).
