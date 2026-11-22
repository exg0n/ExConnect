# ExConnect

Клиент прокси для OpenWrt 25.12.5 с управлением из LuCI.

## Что реализовано

- Импорт ссылок VLESS, VMess, Shadowsocks, Trojan, Hysteria2, SOCKS и HTTP. В одном экземпляре выбирается один исходящий профиль.
- Подписки по HTTPS с ручным обновлением. Поддерживаются списки ссылок в обычном тексте и Base64.
- SOCKS и HTTP на самом роутере. Для клиентов LAN доступен прозрачный режим на nftables TPROXY с выбранными интерфейсами.
- Маршрутизация по доменам и IP-адресам. Правила могут направлять трафик через профиль, напрямую или блокировать его.
- Текстовый редактор маршрутизации RoutingA с правилами по доменам, IP и распознанному протоколу.
- Проверка задержки HTTPS и скорости скачивания для сохранённого профиля. Журнал ExConnect доступен в LuCI.
- Пользовательские `geoip.dat` и `geosite.dat` по HTTPS с готовыми адресами RunetFreedom. Для произвольного имени файла используется синтаксис Xray `ext:<имя.dat>:<тег>`.
- Управление профилями, подписками, правилами и службой в LuCI. Русский и английский интерфейс используют выбранный язык LuCI.

## Установка на роутер

Понадобятся OpenWrt **25.12.5**, доступ по SSH под `root`, свободное место для Xray и доступ с роутера к GitHub и репозиториям OpenWrt. Проверьте версию и свободное место на роутере:

```sh
ubus call system board
df -h /overlay /tmp
```

### Автоматическое скачивание и установка

Выполните одну команду в SSH-сессии роутера под `root`:

```sh
(f=$(mktemp) && trap 'rm -f "$f"' EXIT && wget -T 30 -O "$f" https://raw.githubusercontent.com/exg0n/ExConnect/main/scripts/install-openwrt.sh && sh "$f")
```

Установщик скачивает архив с обоими `.apk` через `raw.githubusercontent.com`. Тот же архив доступен в [GitHub Releases](https://github.com/exg0n/ExConnect/releases/latest). `apk` устанавливает Xray и остальные зависимости из репозиториев OpenWrt. По окончании откройте **Службы → ExConnect** в LuCI. Публикация новой версии проходит после проверок на x86/64 и ARM64 (NanoPi R3S).

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
2. На вкладке **Профили и подписки** добавьте ссылку или сохраните URL подписки и нажмите **Обновить подписку**.
3. В **Настройках** выберите профиль и режим, включите службу и сохраните параметры. В **Обзоре** проверьте конфигурацию и примените её к службе.
4. Для прозрачного режима укажите интерфейс клиентской сети, например `br-lan`. Сначала проверьте профиль в режиме локального прокси. Если на роутере запущен Podkop или другой сервис перехвата трафика LAN, остановите его перед включением прозрачного режима ExConnect.
5. Для списков `.dat` добавьте HTTPS-источник в **Файлах правил**, сохраните его и загрузите. Добавьте соответствующие доменные или IP-условия в правила маршрутизации и снова примените конфигурацию службы.

Для Hysteria2 подходит TLS-сертификат от доверенного центра. Для собственного сертификата укажите `pinSHA256` в ссылке. См. [документацию Hysteria в Xray](https://xtls.github.io/en/config/outbounds/hysteria.html) и [документацию маршрутизации Xray](https://xtls.github.io/en/config/routing.html).

### RoutingA

В разделе **Маршрутизация** выберите редактор **RoutingA** и вставьте правила. Первое совпадение определяет маршрут. Запись `default:` применяется к остальному трафику. Сохранённые правила таблицы остаются доступны при переключении редактора.

```text
default: direct
protocol(bittorrent)->direct
domain(geosite:ru-available-only-inside)->direct
domain(geosite:ru-blocked, geosite:refilter, geosite:antifilter-download-community)->proxy
domain(geosite:category-ads-all)->block
domain(geosite:win-update, geosite:win-extra)->proxy
domain(domain:animeon.cc, domain:shikimori.io, domain:mermaidchart.com, domain:qbittorrent.org, domain:wattpad.com)->proxy
geoip(telegram)->proxy
# Свой IP или подсеть
ip(203.0.113.0/24)->proxy
```

Для категорий из примера добавьте и загрузите базы RunetFreedom под именами `geosite-runetfreedom.dat` и `geoip-runetfreedom.dat` на вкладке **Данные для правил**. При наличии этих источников редактор подставляет их для `geosite:` и `geoip:`. Чтобы указать конкретную базу, используйте `domain(ext:site.dat:tag)` или `ip(ext:ip.dat:tag)`. Тег `wattpad` для правила GeoIP должен присутствовать в выбранной базе. В примере Wattpad задан по домену. Правила по протоколу зависят от распознавания Xray и могут пропускать зашифрованный BitTorrent.

После сохранения проверьте и примените конфигурацию в **Обзоре**.

### Диагностика

В разделе **Диагностика** выберите сохранённый профиль и нажмите **Проверить пинг** или **Измерить скорость загрузки**. Пинг измеряет время до ответа по HTTPS. Тест скорости скачивает до 2 МБ. Оба теста открывают отдельное соединение через профиль без запуска основной службы и без перехвата трафика LAN. На этой же вкладке доступен журнал ExConnect.

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
