#!/bin/bash

# ============================================================================
# ЕДИНЫЙ СКРИПТ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ XRAY REALITY
# Версия: 2.0 - Полная интеграция VLESS библиотеки
# ============================================================================
# Функции: просмотр, добавление, удаление пользователей
# Поддерживает все виды транспорта и параметры VLESS
# ============================================================================

# set -e

# ----------------------------------------------------------------------------
# ЦВЕТА ДЛЯ ВЫВОДА
# ----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ----------------------------------------------------------------------------
IS_MARZBAN="false"
CONFIG=""
DOMAIN=""
PRIVATE_KEY=""
PBK=""
SID=""
XHTTP_PATH=""
NETWORK="tcp"
FLOW="xtls-rprx-vision"
FINGERPRINT="chrome"
CLIENTS_COUNT=0
SNI_DOMAIN=""
SERVER_ADDR=""
VLESS_INBOUND_INDEX=0

# Дополнительные параметры для расширенной конфигурации
XHTTP_EXTRA=""
FINALMASK=""
ALPN=""
HEADER_TYPE=""
HOST=""
MODE="auto"
SEED=""
MTU=""
AUTHORITY=""
SERVICE_NAME=""
GRPC_MODE=""
SPIDERX=""
ALLOW_INSECURE=""
ECH=""
VCN=""
PCS=""
MLDSA65_VERIFY=""
CONGESTION_CONTROL=""
HY2_REALM_URL=""
SALAMANDER_PASS=""
GECKO_MIN=""
GECKO_MAX=""
PORTS=""
HOP_INTERVAL=""
UP_MBPS=""
DOWN_MBPS=""
MUX_ENABLED=""
UOT_ENABLED=""
OUTBOUND_TAG=""
HTTP_HEADERS=""
WG_PUBLIC_KEY=""
WG_PRESHARED_KEY=""
WG_ADDRESS=""
WG_RESERVED=""
WG_MTU=""
NAIVE_QUIC=""
INSECURE_CONCURRENCY=""

trap 'echo -e "\n${YELLOW} Прервано пользователем${NC}"; exit 0' INT TERM

# ----------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ----------------------------------------------------------------------------
print_info() { echo -e "${BLUE} $1${NC}"; }
print_success() { echo -e "${GREEN} $1${NC}"; }
print_error() { echo -e "${RED} $1${NC}"; }
print_warning() { echo -e "${YELLOW} $1${NC}"; }
print_header() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ----------------------------------------------------------------------------
# VLESS БИБЛИОТЕКА (ВСТРОЕННАЯ)
# ----------------------------------------------------------------------------

# Цвета для вывода библиотеки
VLESS_COLOR_RESET='\033[0m'
VLESS_COLOR_RED='\033[0;31m'
VLESS_COLOR_GREEN='\033[0;32m'
VLESS_COLOR_YELLOW='\033[0;33m'
VLESS_COLOR_BLUE='\033[0;34m'
VLESS_COLOR_CYAN='\033[0;36m'

# ----------------------------------------------------------------------------
# URL кодирование (аналог JavaScript encodeURIComponent)
# ----------------------------------------------------------------------------
vless_urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0; pos<strlen; pos++ )); do
        c="${string:$pos:1}"
        case "$c" in
            [-_.~a-zA-Z0-9]) 
                encoded="${encoded}${c}"
                ;;
            *)
                printf -v o '%%%02x' "'$c"
                encoded="${encoded}${o}"
                ;;
        esac
    done
    echo "$encoded"
}

# ----------------------------------------------------------------------------
# URL декодирование
# ----------------------------------------------------------------------------
vless_urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# ----------------------------------------------------------------------------
# Base64 URL-safe кодирование (без padding, - вместо +, _ вместо /)
# ----------------------------------------------------------------------------
vless_base64url_encode() {
    local input="$1"
    echo -n "$input" | base64 | tr '+/' '-_' | tr -d '='
}

# ----------------------------------------------------------------------------
# Base64 URL-safe декодирование
# ----------------------------------------------------------------------------
vless_base64url_decode() {
    local input="$1"
    local len=${#input}
    local mod=$((len % 4))
    
    if [ $mod -eq 2 ]; then
        input="${input}=="
    elif [ $mod -eq 3 ]; then
        input="${input}="
    fi
    
    echo -n "$input" | tr '-_' '+/' | base64 -d 2>/dev/null
}

# ----------------------------------------------------------------------------
# Генерация VLESS ссылки с поддержкой всех параметров v2rayN
# ----------------------------------------------------------------------------
# Использование: vless_generate_link <uuid> <address> <port> [options]
#
# Опции:
#   --remarks <text>              - Псевдоним сервера
#   --encryption <text>           - Метод шифрования (по умолчанию: none)
#   --flow <text>                 - Управление потоком (xtls-rprx-vision, и т.д.)
#   --security <text>             - Безопасность: tls, reality, или пусто
#   --sni <text>                  - Server Name Indication
#   --fp <text>                   - TLS fingerprint
#   --alpn <text>                 - ALPN значения (через запятую)
#   --allow-insecure              - Разрешить небезопасное (пропуск проверки сертификата)
#   --insecure                    - То же что и allow-insecure
#   --public-key <text>           - Reality публичный ключ (pbk)
#   --short-id <text>             - Reality короткий ID (sid)
#   --spiderx <text>              - SpiderX путь
#   --mldsa65-verify <text>       - ML-DSA-65 верификация
#   --ech <text>                  - ECH конфиг список
#   --vcn <text>                  - Проверка имени сертификата пира
#   --pcs <text>                  - Закрепленный SHA-256 сертификата
#   --type <text>                 - Тип транспорта (raw, xhttp, grpc, ws, httpupgrade, kcp)
#   --host <text>                 - Host заголовок
#   --path <text>                 - Путь
#   --mode <text>                 - xhttp режим (auto, packet-up, stream-up, stream-one)
#   --header-type <text>          - Тип маскировки для raw/kcp
#   --seed <text>                 - KCP seed
#   --mtu <number>                - KCP MTU
#   --authority <text>            - gRPC authority
#   --service-name <text>         - gRPC имя сервиса
#   --grpc-mode <text>            - gRPC режим (gun, multi)
#   --extra <json>                - Дополнительные XHTTP настройки (JSON объект)
#   --finalmask <json>            - Finalmask настройки (JSON объект)
#   --extra-json <json>           - Полный extra JSON (переопределяет отдельные параметры)
#   --outbound-tag <text>         - Outbound тег для маршрутизации
#   --mux-enabled                 - Включить Mux мультиплексирование
#   --uot                         - Включить UDP over TCP
#   --congestion-control <text>   - Управление перегрузками (для Hysteria2/TUIC)
#   --hy2-realm-url <text>        - Hysteria2 Realm URL
#   --salamander-pass <text>      - Hysteria2 пароль обфускации
#   --gecko-min <number>          - Gecko минимальный размер пакета
#   --gecko-max <number>          - Gecko максимальный размер пакета
#   --naive-quic                  - NaiveProxy QUIC режим
#   --insecure-concurrency <num>  - Небезопасная конкурентность для NaiveProxy
#   --wg-public-key <text>        - WireGuard публичный ключ
#   --wg-preshared-key <text>     - WireGuard предварительный ключ
#   --wg-address <text>           - WireGuard адрес интерфейса
#   --wg-reserved <text>          - WireGuard зарезервированные байты
#   --wg-mtu <number>             - WireGuard MTU
#   --http-headers <json>         - HTTP outbound заголовки JSON
#   --ports <text>                - Диапазон портов для hopping
#   --hop-interval <text>         - Интервал hopping портов
#   --up-mbps <number>            - Hysteria2 загрузка Mbps
#   --down-mbps <number>          - Hysteria2 скачивание Mbps
# ============================================================================
vless_generate_link() {
    local uuid="$1"
    local address="$2"
    local port="$3"
    
    if [ -z "$uuid" ] || [ -z "$address" ] || [ -z "$port" ]; then
        echo "ERROR: UUID, address and port are required" >&2
        return 1
    fi
    
    # Значения по умолчанию
    local remarks=""
    local encryption="none"
    local flow=""
    local security=""
    local sni=""
    local fp=""
    local alpn=""
    local allow_insecure=""
    local public_key=""
    local short_id=""
    local spiderx=""
    local mldsa65_verify=""
    local ech=""
    local vcn=""
    local pcs=""
    local type="raw"
    local host=""
    local path=""
    local mode=""
    local header_type=""
    local seed=""
    local mtu=""
    local authority=""
    local service_name=""
    local grpc_mode=""
    local extra_json=""
    local finalmask=""
    local outbound_tag=""
    local mux_enabled=""
    local uot=""
    local congestion_control=""
    local hy2_realm_url=""
    local salamander_pass=""
    local gecko_min=""
    local gecko_max=""
    local naive_quic=""
    local insecure_concurrency=""
    local wg_public_key=""
    local wg_preshared_key=""
    local wg_address=""
    local wg_reserved=""
    local wg_mtu=""
    local http_headers=""
    local ports=""
    local hop_interval=""
    local up_mbps=""
    local down_mbps=""
    
    # Парсинг аргументов
    while [ $# -gt 0 ]; do
        case "$1" in
            --remarks) remarks="$2"; shift 2 ;;
            --encryption) encryption="$2"; shift 2 ;;
            --flow) flow="$2"; shift 2 ;;
            --security) security="$2"; shift 2 ;;
            --sni) sni="$2"; shift 2 ;;
            --fp) fp="$2"; shift 2 ;;
            --alpn) alpn="$2"; shift 2 ;;
            --allow-insecure|--insecure) allow_insecure="1"; shift ;;
            --public-key) public_key="$2"; shift 2 ;;
            --short-id) short_id="$2"; shift 2 ;;
            --spiderx) spiderx="$2"; shift 2 ;;
            --mldsa65-verify) mldsa65_verify="$2"; shift 2 ;;
            --ech) ech="$2"; shift 2 ;;
            --vcn) vcn="$2"; shift 2 ;;
            --pcs) pcs="$2"; shift 2 ;;
            --type) type="$2"; shift 2 ;;
            --host) host="$2"; shift 2 ;;
            --path) path="$2"; shift 2 ;;
            --mode) mode="$2"; shift 2 ;;
            --header-type) header_type="$2"; shift 2 ;;
            --seed) seed="$2"; shift 2 ;;
            --mtu) mtu="$2"; shift 2 ;;
            --authority) authority="$2"; shift 2 ;;
            --service-name) service_name="$2"; shift 2 ;;
            --grpc-mode) grpc_mode="$2"; shift 2 ;;
            --extra) extra_json="$2"; shift 2 ;;
            --finalmask) finalmask="$2"; shift 2 ;;
            --extra-json) extra_json="$2"; shift 2 ;;
            --outbound-tag) outbound_tag="$2"; shift 2 ;;
            --mux-enabled) mux_enabled="true"; shift ;;
            --uot) uot="true"; shift ;;
            --congestion-control) congestion_control="$2"; shift 2 ;;
            --hy2-realm-url) hy2_realm_url="$2"; shift 2 ;;
            --salamander-pass) salamander_pass="$2"; shift 2 ;;
            --gecko-min) gecko_min="$2"; shift 2 ;;
            --gecko-max) gecko_max="$2"; shift 2 ;;
            --naive-quic) naive_quic="true"; shift ;;
            --insecure-concurrency) insecure_concurrency="$2"; shift 2 ;;
            --wg-public-key) wg_public_key="$2"; shift 2 ;;
            --wg-preshared-key) wg_preshared_key="$2"; shift 2 ;;
            --wg-address) wg_address="$2"; shift 2 ;;
            --wg-reserved) wg_reserved="$2"; shift 2 ;;
            --wg-mtu) wg_mtu="$2"; shift 2 ;;
            --http-headers) http_headers="$2"; shift 2 ;;
            --ports) ports="$2"; shift 2 ;;
            --hop-interval) hop_interval="$2"; shift 2 ;;
            --up-mbps) up_mbps="$2"; shift 2 ;;
            --down-mbps) down_mbps="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Построение параметров запроса
    local query=""
    local first_param=1
    
    # Вспомогательная функция для добавления параметра
    _add_param() {
        local key="$1"
        local value="$2"
        if [ -n "$value" ]; then
            if [ $first_param -eq 1 ]; then
                query="?"
                first_param=0
            else
                query="${query}&"
            fi
            query="${query}${key}=$(vless_urlencode "$value")"
        fi
    }
    
    # Добавление стандартных параметров
    _add_param "encryption" "$encryption"
    _add_param "flow" "$flow"
    _add_param "security" "$security"
    _add_param "sni" "$sni"
    _add_param "fp" "$fp"
    _add_param "alpn" "$alpn"
    
    # Reality параметры
    _add_param "pbk" "$public_key"
    _add_param "sid" "$short_id"
    _add_param "spx" "$spiderx"
    _add_param "pqv" "$mldsa65_verify"
    
    # ECH и закрепление сертификата
    _add_param "ech" "$ech"
    _add_param "vcn" "$vcn"
    _add_param "pcs" "$pcs"
    
    # Транспортные параметры
    local transport_type="$type"
    if [ "$transport_type" = "raw" ]; then
        transport_type="tcp"
    fi
    _add_param "type" "$transport_type"
    
    # Транспортно-специфичные параметры
    case "$type" in
        raw|tcp)
            _add_param "headerType" "$header_type"
            _add_param "host" "$host"
            _add_param "path" "$path"
            ;;
        kcp)
            _add_param "headerType" "$header_type"
            _add_param "seed" "$seed"
            [ -n "$mtu" ] && _add_param "mtu" "$mtu"
            ;;
        ws|httpupgrade)
            _add_param "host" "$host"
            _add_param "path" "$path"
            ;;
        xhttp)
            _add_param "host" "$host"
            _add_param "path" "$path"
            _add_param "mode" "$mode"
            ;;
        grpc)
            _add_param "authority" "$authority"
            _add_param "serviceName" "$service_name"
            _add_param "mode" "$grpc_mode"
            ;;
    esac
    
    # Allow Insecure (два способа для совместимости)
    if [ "$allow_insecure" = "1" ]; then
        if [ $first_param -eq 1 ]; then
            query="?"
            first_param=0
        else
            query="${query}&"
        fi
        query="${query}insecure=1"
        query="${query}&allowInsecure=1"
    fi
    
    # Построение JSON объекта для расширенных настроек
    local extra_final=""
    if [ -n "$extra_json" ] || [ -n "$finalmask" ] || [ -n "$http_headers" ] || [ -n "$congestion_control" ] || [ -n "$hy2_realm_url" ] || [ -n "$salamander_pass" ] || [ -n "$ports" ] || [ -n "$hop_interval" ] || [ -n "$up_mbps" ] || [ -n "$down_mbps" ] || [ -n "$gecko_min" ] || [ -n "$gecko_max" ]; then
        extra_final="{"
        local extra_first=1
        
        _add_extra_field() {
            local key="$1"
            local value="$2"
            if [ -n "$value" ]; then
                if [ $extra_first -eq 1 ]; then
                    extra_first=0
                else
                    extra_final="${extra_final},"
                fi
                extra_final="${extra_final}\"${key}\":${value}"
            fi
        }
        
        # Добавление xhttp extra если предоставлен
        if [ -n "$extra_json" ]; then
            if echo "$extra_json" | jq -e . >/dev/null 2>&1 2>/dev/null; then
                _add_extra_field "xhttp" "$extra_json"
            else
                if [ -n "$extra_json" ]; then
                    _add_extra_field "xhttp" "{$extra_json}"
                fi
            fi
        fi
        
        # Добавление finalmask если предоставлен
        if [ -n "$finalmask" ]; then
            _add_extra_field "finalmask" "$finalmask"
        fi
        
        # Добавление управления перегрузками
        if [ -n "$congestion_control" ]; then
            _add_extra_field "congestionControl" "\"$congestion_control\""
        fi
        
        # Добавление Hysteria2 Realm URL
        if [ -n "$hy2_realm_url" ]; then
            _add_extra_field "hy2RealmUrl" "\"$hy2_realm_url\""
        fi
        
        # Добавление Salamander пароля
        if [ -n "$salamander_pass" ]; then
            _add_extra_field "salamanderPass" "\"$salamander_pass\""
        fi
        
        # Добавление Gecko размера пакетов
        if [ -n "$gecko_min" ] && [ -n "$gecko_max" ]; then
            _add_extra_field "geckoMinPacketSize" "\"$gecko_min\""
            _add_extra_field "geckoMaxPacketSize" "\"$gecko_max\""
        fi
        
        # Добавление портов (hopping)
        if [ -n "$ports" ]; then
            _add_extra_field "ports" "\"$ports\""
        fi
        
        # Добавление интервала hopping
        if [ -n "$hop_interval" ]; then
            _add_extra_field "hopInterval" "\"$hop_interval\""
        fi
        
        # Добавление пропускной способности
        if [ -n "$up_mbps" ]; then
            _add_extra_field "upMbps" "$up_mbps"
        fi
        if [ -n "$down_mbps" ]; then
            _add_extra_field "downMbps" "$down_mbps"
        fi
        
        # Добавление HTTP заголовков
        if [ -n "$http_headers" ]; then
            _add_extra_field "httpHeaders" "$http_headers"
        fi
        
        extra_final="${extra_final}}"
        
        # Добавление только если не пусто
        if [ "$extra_final" != "{}" ] && [ "$extra_final" != "{" ]; then
            _add_param "extra" "$extra_final"
        fi
    fi
    
    # Формирование VLESS URL
    local userinfo="${uuid}"
    local userinfo_encoded=$(vless_urlencode "$userinfo")
    local remarks_encoded=$(vless_urlencode "$remarks")
    
    # Обработка IPv6 адресов (добавление скобок если нужно)
    local address_formatted="$address"
    if [[ "$address" =~ .*:.* ]] && [[ ! "$address" =~ ^\[.*\]$ ]]; then
        address_formatted="[$address]"
    fi
    
    local url="vless://${userinfo_encoded}@${address_formatted}:${port}${query}"
    
    # Добавление фрагмента с remarks
    if [ -n "$remarks" ]; then
        url="${url}#${remarks_encoded}"
    fi
    
    echo "$url"
}

# ----------------------------------------------------------------------------
# ГЕНЕРАЦИЯ ВНУТРЕННЕЙ ССЫЛКИ V2RAYN (v2rayn://vless/{base64url-json})
# ----------------------------------------------------------------------------
vless_generate_internal_link() {
    local uuid="$1"
    local address="$2"
    local port="$3"
    
    if [ -z "$uuid" ] || [ -z "$address" ] || [ -z "$port" ]; then
        echo "ERROR: UUID, address and port are required" >&2
        return 1
    fi
    
    # Значения по умолчанию
    local remarks=""
    local encryption="none"
    local flow=""
    local security=""
    local sni=""
    local fp=""
    local alpn=""
    local allow_insecure="false"
    local public_key=""
    local short_id=""
    local spiderx=""
    local mldsa65_verify=""
    local ech=""
    local vcn=""
    local pcs=""
    local type="raw"
    local host=""
    local path=""
    local mode=""
    local header_type=""
    local seed=""
    local mtu=""
    local authority=""
    local service_name=""
    local grpc_mode=""
    local extra_json=""
    local finalmask=""
    local outbound_tag=""
    local mux_enabled="false"
    local uot="false"
    local congestion_control=""
    local hy2_realm_url=""
    local salamander_pass=""
    local gecko_min=""
    local gecko_max=""
    local naive_quic="false"
    local insecure_concurrency=""
    local wg_public_key=""
    local wg_preshared_key=""
    local wg_address=""
    local wg_reserved=""
    local wg_mtu=""
    local http_headers=""
    local ports=""
    local hop_interval=""
    local up_mbps=""
    local down_mbps=""
    local config_type=5  # VLESS = 5 (из EConfigType.cs)
    
    # Парсинг аргументов
    while [ $# -gt 0 ]; do
        case "$1" in
            --remarks) remarks="$2"; shift 2 ;;
            --encryption) encryption="$2"; shift 2 ;;
            --flow) flow="$2"; shift 2 ;;
            --security) security="$2"; shift 2 ;;
            --sni) sni="$2"; shift 2 ;;
            --fp) fp="$2"; shift 2 ;;
            --alpn) alpn="$2"; shift 2 ;;
            --allow-insecure) allow_insecure="true"; shift ;;
            --public-key) public_key="$2"; shift 2 ;;
            --short-id) short_id="$2"; shift 2 ;;
            --spiderx) spiderx="$2"; shift 2 ;;
            --mldsa65-verify) mldsa65_verify="$2"; shift 2 ;;
            --ech) ech="$2"; shift 2 ;;
            --vcn) vcn="$2"; shift 2 ;;
            --pcs) pcs="$2"; shift 2 ;;
            --type) type="$2"; shift 2 ;;
            --host) host="$2"; shift 2 ;;
            --path) path="$2"; shift 2 ;;
            --mode) mode="$2"; shift 2 ;;
            --header-type) header_type="$2"; shift 2 ;;
            --seed) seed="$2"; shift 2 ;;
            --mtu) mtu="$2"; shift 2 ;;
            --authority) authority="$2"; shift 2 ;;
            --service-name) service_name="$2"; shift 2 ;;
            --grpc-mode) grpc_mode="$2"; shift 2 ;;
            --extra) extra_json="$2"; shift 2 ;;
            --finalmask) finalmask="$2"; shift 2 ;;
            --outbound-tag) outbound_tag="$2"; shift 2 ;;
            --mux-enabled) mux_enabled="true"; shift ;;
            --uot) uot="true"; shift ;;
            --congestion-control) congestion_control="$2"; shift 2 ;;
            --hy2-realm-url) hy2_realm_url="$2"; shift 2 ;;
            --salamander-pass) salamander_pass="$2"; shift 2 ;;
            --gecko-min) gecko_min="$2"; shift 2 ;;
            --gecko-max) gecko_max="$2"; shift 2 ;;
            --naive-quic) naive_quic="true"; shift ;;
            --insecure-concurrency) insecure_concurrency="$2"; shift 2 ;;
            --wg-public-key) wg_public_key="$2"; shift 2 ;;
            --wg-preshared-key) wg_preshared_key="$2"; shift 2 ;;
            --wg-address) wg_address="$2"; shift 2 ;;
            --wg-reserved) wg_reserved="$2"; shift 2 ;;
            --wg-mtu) wg_mtu="$2"; shift 2 ;;
            --http-headers) http_headers="$2"; shift 2 ;;
            --ports) ports="$2"; shift 2 ;;
            --hop-interval) hop_interval="$2"; shift 2 ;;
            --up-mbps) up_mbps="$2"; shift 2 ;;
            --down-mbps) down_mbps="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Построение JSON ProfileItem
    local json="{
        \"ConfigType\": $config_type,
        \"ConfigVersion\": 4,
        \"Address\": \"$address\",
        \"Port\": $port,
        \"Password\": \"$uuid\","
    
    [ -n "$remarks" ] && json="$json \"Remarks\": \"$remarks\","
    [ -n "$encryption" ] && json="$json \"Security\": \"$encryption\","
    [ -n "$flow" ] && json="$json \"Flow\": \"$flow\","
    [ -n "$security" ] && json="$json \"StreamSecurity\": \"$security\","
    [ -n "$sni" ] && json="$json \"Sni\": \"$sni\","
    [ -n "$fp" ] && json="$json \"Fingerprint\": \"$fp\","
    [ -n "$alpn" ] && json="$json \"Alpn\": \"$alpn\","
    [ "$allow_insecure" = "true" ] && json="$json \"AllowInsecure\": \"true\","
    [ -n "$public_key" ] && json="$json \"PublicKey\": \"$public_key\","
    [ -n "$short_id" ] && json="$json \"ShortId\": \"$short_id\","
    [ -n "$spiderx" ] && json="$json \"SpiderX\": \"$spiderx\","
    [ -n "$mldsa65_verify" ] && json="$json \"Mldsa65Verify\": \"$mldsa65_verify\","
    [ -n "$ech" ] && json="$json \"EchConfigList\": \"$ech\","
    [ -n "$vcn" ] && json="$json \"VerifyPeerCertByName\": \"$vcn\","
    [ -n "$pcs" ] && json="$json \"CertSha\": \"$pcs\","
    [ -n "$type" ] && json="$json \"Network\": \"$type\","
    [ -n "$host" ] && json="$json \"RequestHost\": \"$host\","
    [ -n "$path" ] && json="$json \"Path\": \"$path\","
    [ -n "$header_type" ] && json="$json \"HeaderType\": \"$header_type\","
    [ -n "$seed" ] && json="$json \"Extra\": \"$seed\","
    [ -n "$mtu" ] && json="$json \"KcpMtu\": $mtu,"
    [ -n "$authority" ] && json="$json \"GrpcAuthority\": \"$authority\","
    [ -n "$service_name" ] && json="$json \"GrpcServiceName\": \"$service_name\","
    [ -n "$grpc_mode" ] && json="$json \"GrpcMode\": \"$grpc_mode\","
    [ -n "$mode" ] && json="$json \"XhttpMode\": \"$mode\","
    [ -n "$extra_json" ] && json="$json \"Extra\": \"$extra_json\","
    [ -n "$finalmask" ] && json="$json \"Finalmask\": \"$finalmask\","
    [ -n "$outbound_tag" ] && json="$json \"OutboundTag\": \"$outbound_tag\","
    [ "$mux_enabled" = "true" ] && json="$json \"MuxEnabled\": true,"
    [ "$uot" = "true" ] && json="$json \"Uot\": true,"
    [ -n "$congestion_control" ] && json="$json \"CongestionControl\": \"$congestion_control\","
    [ -n "$hy2_realm_url" ] && json="$json \"Hy2RealmUrl\": \"$hy2_realm_url\","
    [ -n "$salamander_pass" ] && json="$json \"SalamanderPass\": \"$salamander_pass\","
    [ -n "$gecko_min" ] && json="$json \"GeckoMinPacketSize\": \"$gecko_min\","
    [ -n "$gecko_max" ] && json="$json \"GeckoMaxPacketSize\": \"$gecko_max\","
    [ "$naive_quic" = "true" ] && json="$json \"NaiveQuic\": true,"
    [ -n "$insecure_concurrency" ] && json="$json \"InsecureConcurrency\": $insecure_concurrency,"
    [ -n "$wg_public_key" ] && json="$json \"WgPublicKey\": \"$wg_public_key\","
    [ -n "$wg_preshared_key" ] && json="$json \"WgPresharedKey\": \"$wg_preshared_key\","
    [ -n "$wg_address" ] && json="$json \"WgInterfaceAddress\": \"$wg_address\","
    [ -n "$wg_reserved" ] && json="$json \"WgReserved\": \"$wg_reserved\","
    [ -n "$wg_mtu" ] && json="$json \"WgMtu\": $wg_mtu,"
    [ -n "$http_headers" ] && json="$json \"HttpHeaders\": \"$http_headers\","
    [ -n "$ports" ] && json="$json \"Ports\": \"$ports\","
    [ -n "$hop_interval" ] && json="$json \"HopInterval\": \"$hop_interval\","
    [ -n "$up_mbps" ] && json="$json \"UpMbps\": $up_mbps,"
    [ -n "$down_mbps" ] && json="$json \"DownMbps\": $down_mbps,"
    
    # Удаление последней запятой если есть
    json="${json%,}"
    json="$json }"
    
    # Компактный JSON
    local compact_json=$(echo "$json" | jq -c . 2>/dev/null || echo "$json" | tr -d ' \n')
    
    # Кодирование в Base64URL
    local encoded=$(vless_base64url_encode "$compact_json")
    
    echo "v2rayn://vless/${encoded}"
}

# ----------------------------------------------------------------------------
# ПОЛУЧЕНИЕ ПАРАМЕТРОВ КОНФИГУРАЦИИ ИЗ JSON
# ----------------------------------------------------------------------------
vless_parse_config_params() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        print_error "Файл конфигурации не найден: $config_file"
        return 1
    fi
    
    # ============================================================
    # НАЙТИ INBOUND С ПРОТОКОЛОМ VLESS
    # ============================================================
    VLESS_INBOUND_INDEX=$(jq -r '.inbounds | to_entries[] | select(.value.protocol == "vless") | .key' "$config_file" 2>/dev/null | head -1)
    
    if [ -z "$VLESS_INBOUND_INDEX" ] || [ "$VLESS_INBOUND_INDEX" = "null" ]; then
        print_error "Не найден inbound с протоколом vless"
        return 1
    fi
    
    print_info "Найден VLESS inbound с индексом: $VLESS_INBOUND_INDEX"
    
    # ============================================================
    # ПОЛУЧЕНИЕ ПАРАМЕТРОВ ИЗ НАЙДЕННОГО INBOUND
    # ============================================================
    case "$NETWORK" in
    ws|httpupgrade)
        HOST=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.${NETWORK}Settings.host // \"\"" "$config_file" 2>/dev/null)
        ;;
    xhttp)
        HOST=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.xhttpSettings.host // \"\"" "$config_file" 2>/dev/null)
        ;;
    tcp)
        HOST=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.tcpSettings.header.request.headers.Host // \"\"" "$config_file" 2>/dev/null)
        ;;
esac
[ "$HOST" = "null" ] && HOST=""

    # DOMAIN для отображения - берем из realitySettings.serverNames или dest
    DOMAIN=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.serverNames[0] // .inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.dest // \"\"" "$config_file" 2>/dev/null)
    if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
        # Если это dest в формате "domain:port", берем только домен
        DOMAIN=$(echo "$DOMAIN" | cut -d':' -f1)
    else
        DOMAIN=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].listen" "$config_file" 2>/dev/null | sed 's/^"//;s/"$//')
    fi

    SERVER_ADDR=$(ip route get 1 | awk '{print $NF;exit}' 2>/dev/null)
if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR=$(curl -s ifconfig.me 2>/dev/null || echo "127.0.0.1")
fi

    # SNI_DOMAIN для ссылки - берем из serverNames[0] (приоритет)
SNI_DOMAIN=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.serverNames[0] // empty" "$CONFIG" 2>/dev/null)

if [ -z "$SNI_DOMAIN" ] || [ "$SNI_DOMAIN" = "null" ]; then
    SNI_DOMAIN=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.serverName // empty" "$CONFIG" 2>/dev/null)
fi

if [ -z "$SNI_DOMAIN" ] || [ "$SNI_DOMAIN" = "null" ]; then
    # Берем из dest
    SNI_DOMAIN=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.dest // empty" "$CONFIG" 2>/dev/null | cut -d':' -f1)
fi

# Если все еще пусто - используем DOMAIN (НЕ IP!)
if [ -z "$SNI_DOMAIN" ] || [ "$SNI_DOMAIN" = "null" ]; then
    SNI_DOMAIN="$DOMAIN"
fi

# Финальная проверка - если IP, то предупреждение
if [[ "$SNI_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_warning "ВНИМАНИЕ: SNI_DOMAIN определен как IP ($SNI_DOMAIN)"
    print_warning "Для Reality рекомендуется использовать домен!"
fi

    PORT=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].port // 443" "$config_file" 2>/dev/null)
if [ -z "$PORT" ] || [ "$PORT" = "null" ]; then
    PORT=443
fi

    # Private Key
    PRIVATE_KEY=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.privateKey // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "null" ]; then
        print_error "Не найден privateKey в конфиге"
        return 1
    fi
    
    # Генерация публичного ключа
    PBK=$(docker run --rm ghcr.io/xtls/xray-core:latest x25519 -i "$PRIVATE_KEY" 2>/dev/null | grep -E "(PublicKey:|Password \(PublicKey\):)" | head -1 | awk '{print $NF}')
    if [ -z "$PBK" ]; then
        print_error "Не удалось сгенерировать публичный ключ"
        return 1
    fi
    
    # Short ID - берем из realitySettings.shortIds[0]
    SID=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.shortIds[0] // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$SID" ] || [ "$SID" = "null" ]; then
        SID=""
    fi
    
    # ============================================================
    # ПАРАМЕТРЫ ТРАНСПОРТА (из VLESS inbound)
    # ============================================================
    
    # NETWORK
    NETWORK=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.network // \"tcp\"" "$config_file" 2>/dev/null)
    if [ -z "$NETWORK" ] || [ "$NETWORK" = "null" ]; then
        NETWORK="tcp"
    fi
    
    # gRPC параметры
    SERVICE_NAME=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.grpcSettings.serviceName // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$SERVICE_NAME" ] || [ "$SERVICE_NAME" = "null" ]; then
        SERVICE_NAME=""
    fi
    
    GRPC_MODE=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.grpcSettings.mode // \"gun\"" "$config_file" 2>/dev/null)
    if [ -z "$GRPC_MODE" ] || [ "$GRPC_MODE" = "null" ]; then
        GRPC_MODE="gun"
    fi
    
    AUTHORITY=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.grpcSettings.authority // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$AUTHORITY" ] || [ "$AUTHORITY" = "null" ]; then
        AUTHORITY=""
    fi

    ALLOW_INSECURE=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.allowInsecure // false" "$config_file" 2>/dev/null)
if [ "$ALLOW_INSECURE" = "true" ] || [ "$ALLOW_INSECURE" = "1" ]; then
    ALLOW_INSECURE="1"
else
    ALLOW_INSECURE=""
fi
    # XHTTP Path - для xhttp транспорта
case "$NETWORK" in
    xhttp)
        XHTTP_PATH=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.xhttpSettings.path // \"\"" "$config_file" 2>/dev/null | sed 's|^/||')
        ;;
    ws|httpupgrade)
        XHTTP_PATH=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.${NETWORK}Settings.path // \"\"" "$config_file" 2>/dev/null | sed 's|^/||')
        ;;
    *)
        XHTTP_PATH=""
        ;;
esac
    
    # XHTTP Mode
    MODE=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.xhttpSettings.mode // \"auto\"" "$config_file" 2>/dev/null)
    if [ -z "$MODE" ] || [ "$MODE" = "null" ]; then
        MODE="auto"
    fi
    
    # SpiderX - берем из realitySettings.spiderX
    SPIDERX=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.spiderX // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$SPIDERX" ] || [ "$SPIDERX" = "null" ]; then
        SPIDERX=""
    fi
    
    # Fingerprint - берем из realitySettings.fingerprint (если есть)
    FINGERPRINT=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.fingerprint // \"chrome\"" "$config_file" 2>/dev/null)
    if [ -z "$FINGERPRINT" ] || [ "$FINGERPRINT" = "null" ]; then
        FINGERPRINT="chrome"
    fi
    
    # Flow - берем из settings.clients[0].flow
    FLOW=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].settings.clients[0].flow // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$FLOW" ] || [ "$FLOW" = "null" ]; then
        FLOW=""
    fi
    
    # Количество клиентов
    CLIENTS_COUNT=$(jq ".inbounds[$VLESS_INBOUND_INDEX].settings.clients | length" "$config_file" 2>/dev/null)
    if [ -z "$CLIENTS_COUNT" ] || [ "$CLIENTS_COUNT" = "null" ]; then
        CLIENTS_COUNT=0
    fi
    
    # Дополнительные параметры
    ALPN=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.realitySettings.alpn // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$ALPN" ] || [ "$ALPN" = "null" ]; then
        ALPN=""
    fi
    
    # Finalmask
    FINALMASK=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.xhttpSettings.finalmask // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$FINALMASK" ] || [ "$FINALMASK" = "null" ]; then
        FINALMASK=""
    fi
    
    # XHTTP Extra
    XHTTP_EXTRA=$(jq -r ".inbounds[$VLESS_INBOUND_INDEX].streamSettings.xhttpSettings.extra // \"\"" "$config_file" 2>/dev/null)
    if [ -z "$XHTTP_EXTRA" ] || [ "$XHTTP_EXTRA" = "null" ]; then
        XHTTP_EXTRA=""
    fi
    
    return 0
}
# ----------------------------------------------------------------------------
# ГЕНЕРАЦИЯ VLESS ССЫЛКИ НА ОСНОВЕ КОНФИГУРАЦИИ
# ----------------------------------------------------------------------------
create_vless_link() {
    local uuid="$1"
    local email="$2"
    
    if [ -z "$uuid" ] || [ -z "$email" ]; then
        print_error "UUID и email обязательны"
        return 1
    fi
    
    # Используем SERVER_ADDR (IP) для ссылки
    local cmd="vless_generate_link \"$uuid\" \"$SERVER_ADDR\" $PORT"
    
    # Для gRPC используем домен из serverNames, а не IP
    local address="$SNI_DOMAIN"
    if [ -z "$address" ] || [ "$address" = "null" ]; then
        address="$DOMAIN"
    fi
    
[ -z "$PORT" ] && PORT=443
local cmd="vless_generate_link \"$uuid\" \"$address\" $PORT"
    
    # Базовые параметры
    cmd="$cmd --remarks \"$email\""
    cmd="$cmd --encryption \"none\""
    cmd="$cmd --security \"reality\""
    cmd="$cmd --sni \"$SNI_DOMAIN\""
    cmd="$cmd --fp \"$FINGERPRINT\""
    cmd="$cmd --public-key \"$PBK\""
    
    # Добавление short-id если есть
    if [ -n "$SID" ]; then
        cmd="$cmd --short-id \"$SID\""
    fi
    
    # Добавление spiderx если есть
    if [ -n "$SPIDERX" ]; then
        cmd="$cmd --spiderx \"$SPIDERX\""
    fi
    
    # Добавление flow если есть
    if [ -n "$FLOW" ]; then
        cmd="$cmd --flow \"$FLOW\""
    fi
    
    # Транспортные параметры
    case "$NETWORK" in
        xhttp)
            cmd="$cmd --type \"xhttp\""
            if [ -n "$XHTTP_PATH" ]; then
                cmd="$cmd --path \"/$XHTTP_PATH\""
            fi
            if [ -n "$MODE" ]; then
                cmd="$cmd --mode \"$MODE\""
            fi
            if [ -n "$XHTTP_EXTRA" ]; then
                cmd="$cmd --extra \"$XHTTP_EXTRA\""
            fi
            ;;
        ws|httpupgrade)
            cmd="$cmd --type \"$NETWORK\""
if [ -n "$XHTTP_PATH" ]; then
    # Если путь уже начинается с /, не добавляем его
    if [[ "$XHTTP_PATH" =~ ^/ ]]; then
        cmd="$cmd --path \"$XHTTP_PATH\""
    else
        cmd="$cmd --path \"/$XHTTP_PATH\""
    fi
fi
            if [ -n "$HOST" ]; then
                cmd="$cmd --host \"$HOST\""
            fi
            ;;
        grpc)
            cmd="$cmd --type \"grpc\""
            if [ -n "$SERVICE_NAME" ]; then
                cmd="$cmd --service-name \"$SERVICE_NAME\""
            fi
            if [ -n "$GRPC_MODE" ]; then
                cmd="$cmd --grpc-mode \"$GRPC_MODE\""
            fi
            if [ -n "$AUTHORITY" ]; then
                cmd="$cmd --authority \"$AUTHORITY\""
            fi
            ;;
        kcp)
            cmd="$cmd --type \"kcp\""
            if [ -n "$HEADER_TYPE" ]; then
                cmd="$cmd --header-type \"$HEADER_TYPE\""
            fi
            if [ -n "$SEED" ]; then
                cmd="$cmd --seed \"$SEED\""
            fi
            if [ -n "$MTU" ]; then
                cmd="$cmd --mtu \"$MTU\""
            fi
            ;;
        tcp|raw)
            cmd="$cmd --type \"$NETWORK\""
            if [ -n "$HEADER_TYPE" ] && [ "$HEADER_TYPE" = "http" ]; then
                cmd="$cmd --header-type \"$HEADER_TYPE\""
            fi
            if [ -n "$XHTTP_PATH" ]; then
                cmd="$cmd --path \"$XHTTP_PATH\""
            fi
            if [ -n "$HOST" ]; then
                cmd="$cmd --host \"$HOST\""
            fi
            ;;
        *)
            # По умолчанию tcp
            cmd="$cmd --type \"tcp\""
            ;;
    esac
    
    # Добавление finalmask если есть
    if [ -n "$FINALMASK" ]; then
        cmd="$cmd --finalmask \"$FINALMASK\""
    fi
    
    # Добавление allow-insecure если есть
    if [ -n "$ALLOW_INSECURE" ] && [ "$ALLOW_INSECURE" = "1" ]; then
        cmd="$cmd --allow-insecure"
    fi
    
    # Добавление alpn если есть
    if [ -n "$ALPN" ]; then
        cmd="$cmd --alpn \"$ALPN\""
    fi
    
    # Выполнение команды
    eval "$cmd"
}

# ----------------------------------------------------------------------------
# УСТАНОВКА ЗАВИСИМОСТЕЙ
# ----------------------------------------------------------------------------
install_jq() {
    if ! command -v jq &> /dev/null; then
        print_info "Установка jq..."
        apt-get update -qq 2>/dev/null
        apt-get install -y jq -qq 2>/dev/null
        if ! command -v jq &> /dev/null; then
            print_error "Не удалось установить jq"
            exit 1
        fi
        print_success "jq установлен"
    fi
}

install_qrencode() {
    if ! command -v qrencode &> /dev/null; then
        print_info "Установка qrencode для QR кодов..."
        apt-get update -qq 2>/dev/null
        apt-get install -y qrencode -qq 2>/dev/null
        if ! command -v qrencode &> /dev/null; then
            print_warning "Не удалось установить qrencode, QR коды будут недоступны"
            return 1
        fi
        print_success "qrencode установлен"
        return 0
    fi
    return 0
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен"
        exit 1
    fi

    if ! docker ps &> /dev/null; then
        print_error "Docker не запущен или нет прав"
        exit 1
    fi
}

generate_uuid() {
    docker run --rm ghcr.io/xtls/xray-core:latest uuid 2>/dev/null | tr -d '\r'
}

generate_qr() {
    local text="$1"
    if command -v qrencode &>/dev/null; then
        echo "$text" | qrencode -t ansiutf8 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "  (терминальный вывод не поддерживается)"
        fi
    else
        echo -e "${YELLOW} Установите qrencode для отображения QR кодов: apt install qrencode${NC}"
    fi
}

# ----------------------------------------------------------------------------
# УПРАВЛЕНИЕ КОНФИГУРАЦИЕЙ
# ----------------------------------------------------------------------------
get_config_path() {
    local config=""
    if [ -n "$XRAY_CONFIG_PATH" ] && [ -f "$XRAY_CONFIG_PATH" ]; then
        config="$XRAY_CONFIG_PATH"
        IS_MARZBAN="false"
        print_info "Используется кастомный путь: $config"
        echo "$config"
        return
    fi
    if [ -f "/opt/xray-vps-setup/xray/config.json" ]; then
        config="/opt/xray-vps-setup/xray/config.json"
        IS_MARZBAN="false"
    elif [ -f "/opt/xray-vps-setup/marzban/xray_config.json" ]; then
        config="/opt/xray-vps-setup/marzban/xray_config.json"
        IS_MARZBAN="true"
    elif [ -f "/var/lib/marzban/configs/xray_config.json" ]; then
        config="/var/lib/marzban/configs/xray_config.json"
        IS_MARZBAN="true"
    else
        print_error "Конфиг не найден"
        exit 1
    fi
    echo "$config"
}

restart_xray() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        print_error "Ни docker compose, ни docker-compose не найдены в системе"
        return 1
    fi

    if [ "$IS_MARZBAN" = "false" ]; then
        print_info "Перезапуск Xray контейнера..."
        cd /opt/xray-vps-setup

        $DOCKER_COMPOSE_CMD restart xray 2>/dev/null || {
            print_warning "Контейнер xray не найден, перезапуск всех контейнеров..."
            $DOCKER_COMPOSE_CMD restart
        }
        print_success "Контейнеры перезапущены"
    else
        print_warning "Marzban режим: перезапустите вручную при необходимости"
        print_info "$DOCKER_COMPOSE_CMD -f /opt/xray-vps-setup/docker-compose.yml restart marzban"
    fi
}

load_config() {
    CONFIG=$(get_config_path)
    print_info "Конфиг загружен: $CONFIG"

    if [ "$IS_MARZBAN" = "true" ]; then
        print_warning "Обнаружен Marzban режим"
    fi

    # Проверка JSON
    if ! jq empty "$CONFIG" 2>/dev/null; then
        print_error "Конфиг файл содержит невалидный JSON"
        exit 1
    fi

    # Получение параметров через функцию библиотеки
    if ! vless_parse_config_params "$CONFIG"; then
        print_error "Не удалось распарсить конфигурацию"
        exit 1
    fi
    
    print_success "Конфигурация загружена: $DOMAIN:$NETWORK"
}

# ----------------------------------------------------------------------------
# ОТОБРАЖЕНИЕ ПОЛЬЗОВАТЕЛЕЙ
# ----------------------------------------------------------------------------
show_users_table() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                          XRAY REALITY USERS LIST                          ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " Server: $DOMAIN:443"
    echo " Public Key: $PBK"
    echo " Short ID: ${SID:-"(не задан)"}"
    echo " Transport: $NETWORK"
    [ "$NETWORK" = "xhttp" ] && echo "️  Path: /$XHTTP_PATH"
    [ -n "$FINALMASK" ] && echo " Finalmask: (задан)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  %-3s │ %-30s │ %-36s\n" "" "Email" "UUID"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local idx=1
while IFS='|' read -r email uuid; do
    email=${email:-"no-email"}
    uuid=${uuid:-"no-uuid"}
    printf "  %-3s │ %-30s │ %-36s\n" "$idx" "$email" "$uuid"
    user_emails["$idx"]="$email"
    user_uuids["$idx"]="$uuid"
    ((idx++))
done < <(jq -r ".inbounds[$VLESS_INBOUND_INDEX].settings.clients[] | \"\(.email)|\(.id)\"" "$CONFIG" 2>/dev/null)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

show_user_details() {
    local email="$1"
    local uuid="$2"

    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                          USER CONFIGURATION                               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${GREEN} Пользователь:${NC} $email"
    echo -e "${GREEN} UUID:${NC} $uuid"
    echo ""

    vless_link=$(create_vless_link "$uuid" "$email")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW} VLESS Link:${NC}"
    echo "$vless_link"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW} QR Code:${NC}"
    generate_qr "$vless_link" "$email"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Показ внутренней ссылки v2rayN
    echo ""
    echo -e "${YELLOW} v2rayN Internal Link:${NC}"
    local internal_link=$(vless_generate_internal_link "$uuid" "$DOMAIN" 443 \
        --remarks "$email" \
        --security "reality" \
        --sni "$SNI_DOMAIN" \
        --fp "$FINGERPRINT" \
        --public-key "$PBK" \
        ${SID:+--short-id "$SID"} \
        ${FLOW:+--flow "$FLOW"} \
        --type "$NETWORK" \
        ${SERVICE_NAME:+--service-name "$SERVICE_NAME"} \
        ${XHTTP_PATH:+--path "/$XHTTP_PATH"} \
        ${FINALMASK:+--finalmask "$FINALMASK"} \
        2>/dev/null)
    if [ -n "$internal_link" ]; then
        echo "$internal_link"
    else
        print_warning "Внутренняя ссылка недоступна (требуется jq)"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

view_users_menu() {
    declare -A user_emails
    declare -A user_uuids

    show_users_table

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN} Выберите действие:${NC}"
    echo -e "  ${BLUE}1${NC}) Показать конфигурацию конкретного пользователя"
    echo -e "  ${BLUE}2${NC}) Вернуться в главное меню"
    echo ""
    read -p "Ваш выбор (1-2): " action

    case $action in
        1)
            select_single_user
            ;;
        2)
            return
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
}

select_single_user() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                        SELECT USER TO DISPLAY                             ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    declare -a select_emails
    declare -a select_uuids
    local idx=1

while IFS='|' read -r email uuid; do
    email=${email:-"no-email"}
    uuid=${uuid:-"no-uuid"}

    if [ "$uuid" != "no-uuid" ] && [ ${#uuid} -ge 30 ]; then
        echo -e "  ${BLUE}$idx)${NC} $email"
        select_emails+=("$email")
        select_uuids+=("$uuid")
        ((idx++))
    fi
done < <(jq -r ".inbounds[$VLESS_INBOUND_INDEX].settings.clients[] | \"\(.email)|\(.id)\"" "$CONFIG" 2>/dev/null)

    if [ ${#select_emails[@]} -eq 0 ]; then
        print_error "Нет валидных пользователей"
        return
    fi

    echo ""
    echo -e "  ${RED}0${NC}) Назад"
    echo ""
    read -p "Выберите пользователя (0-${#select_emails[@]}): " user_choice

    if [ "$user_choice" -eq 0 ] 2>/dev/null; then
        return
    fi

    if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le ${#select_emails[@]} ] 2>/dev/null; then
        local selected_email="${select_emails[$((user_choice-1))]}"
        local selected_uuid="${select_uuids[$((user_choice-1))]}"
        show_user_details "$selected_email" "$selected_uuid"

        echo ""
        read -p "Нажмите Enter для продолжения..."
        select_single_user
    else
        print_error "Неверный выбор"
    fi
}

# ----------------------------------------------------------------------------
# ДОБАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯ
# ----------------------------------------------------------------------------
add_user() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                    ADD NEW XRAY REALITY USER                              ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " Server: $DOMAIN:443"
    echo " Transport: $NETWORK"
    [ "$NETWORK" = "xhttp" ] && echo "️  Path: /$XHTTP_PATH"
    [ -n "$FINALMASK" ] && echo " Finalmask: задан"
    echo ""

    # Имя пользователя
    while true; do
        echo -n " Enter name for new user (e.g., friend, client1): "
        read USER_EMAIL

        if [ -z "$USER_EMAIL" ]; then
            print_warning "Name не может быть пустым"
            continue
        fi

        if jq -e ".inbounds[$VLESS_INBOUND_INDEX].settings.clients[] | select(.email == \"$USER_EMAIL\")" "$CONFIG" > /dev/null 2>&1; then
            print_error "Пользователь с Name '$USER_EMAIL' уже существует!"
            continue
        fi
        break
    done

    # Генерация UUID
    print_info "Генерация UUID для $USER_EMAIL..."
    NEW_UUID=$(generate_uuid)

    if [ -z "$NEW_UUID" ] || [ ${#NEW_UUID} -lt 30 ]; then
        print_error "Не удалось сгенерировать UUID"
        return
    fi

    print_success "UUID сгенерирован: $NEW_UUID"

    # Создание резервной копии
    BACKUP_FILE="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG" "$BACKUP_FILE"
    print_success "Резервная копия создана: $BACKUP_FILE"

    # Создание нового пользователя
   if [ "$NETWORK" = "xhttp" ]; then
    NEW_CLIENT="{
        \"id\": \"$NEW_UUID\",
        \"email\": \"$USER_EMAIL\"
    }"
else
    # Для gRPC и других транспортов - добавляем flow только если он есть
    if [ -n "$FLOW" ]; then
        NEW_CLIENT="{
            \"id\": \"$NEW_UUID\",
            \"email\": \"$USER_EMAIL\",
            \"flow\": \"$FLOW\"
        }"
    else
        NEW_CLIENT="{
            \"id\": \"$NEW_UUID\",
            \"email\": \"$USER_EMAIL\"
        }"
    fi
fi

    # Добавление пользователя
    print_info "Добавление нового пользователя в конфиг..."
    TMP_FILE=$(mktemp)
    jq ".inbounds[$VLESS_INBOUND_INDEX].settings.clients += [$NEW_CLIENT]" "$CONFIG" > "$TMP_FILE"

    if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
        mv "$TMP_FILE" "$CONFIG"
        print_success "Пользователь добавлен в конфиг"
    else
        print_error "Ошибка при добавлении пользователя"
        rm -f "$TMP_FILE"
        return
    fi

    restart_xray

    # Генерация VLESS ссылки
    vless_link=$(create_vless_link "$NEW_UUID" "$USER_EMAIL")

    # Результат
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                          USER ADDED SUCCESSFULLY!                         ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " New User: $USER_EMAIL"
    echo " UUID: $NEW_UUID"
    echo " Transport: $NETWORK"
    [ "$NETWORK" = "xhttp" ] && echo "️  Path: /$XHTTP_PATH"
    [ -n "$FINALMASK" ] && echo " Finalmask: задан"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " VLESS Link:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$vless_link"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    generate_qr "$vless_link" "$USER_EMAIL"
    echo ""
    echo " Резервная копия: $BACKUP_FILE"

    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# ----------------------------------------------------------------------------
# УДАЛЕНИЕ ПОЛЬЗОВАТЕЛЯ
# ----------------------------------------------------------------------------
delete_user() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                       DELETE XRAY REALITY USER                            ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    declare -a delete_emails
    declare -a delete_uuids
    local idx=1

    # Получение всех пользователей
while IFS='|' read -r email uuid; do
    email=${email:-"no-email"}
    uuid=${uuid:-"no-uuid"}

    if [ "$uuid" != "no-uuid" ] && [ ${#uuid} -ge 30 ]; then
        delete_emails+=("$email")
        delete_uuids+=("$uuid")
        ((idx++))
    fi
done < <(jq -r ".inbounds[$VLESS_INBOUND_INDEX].settings.clients[] | \"\(.email)|\(.id)\"" "$CONFIG" 2>/dev/null)

    # Проверка пользователей
    if [ ${#delete_emails[@]} -eq 0 ]; then
        print_error "Нет пользователей для удаления"
        read -p "Нажмите Enter для продолжения..."
        return
    fi

    if [ ${#delete_emails[@]} -eq 1 ]; then
        print_error " НЕЛЬЗЯ УДАЛИТЬ ЕДИНСТВЕННОГО ПОЛЬЗОВАТЕЛЯ!"
        print_warning "В системе должен оставаться хотя бы один пользователь для работы XRAY."
        echo ""
        echo -e "${RED}Текущий пользователь:${NC} ${delete_emails[0]}"
        echo ""
        read -p "Нажмите Enter для продолжения..."
        return
    fi

    echo -e "${GREEN}Список пользователей (всего: ${#delete_emails[@]}):${NC}"
    echo ""

    idx=1
    for i in "${!delete_emails[@]}"; do
        echo -e "  ${BLUE}$((idx))${NC}) ${delete_emails[$i]} (UUID: ${delete_uuids[$i]:0:8}...)"
        ((idx++))
    done

    echo ""
    echo -e "  ${RED}0${NC}) Назад"
    echo ""
    read -p "Выберите пользователя для удаления (0-${#delete_emails[@]}): " user_choice

    if [ "$user_choice" -eq 0 ] 2>/dev/null; then
        return
    fi

    if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le ${#delete_emails[@]} ] 2>/dev/null; then
        local selected_email="${delete_emails[$((user_choice-1))]}"
        local selected_uuid="${delete_uuids[$((user_choice-1))]}"

        echo ""
        print_warning "Вы собираетесь удалить пользователя: $selected_email"
        echo -e "${RED}UUID: $selected_uuid${NC}"
        echo ""
        echo -n "Вы уверены? (y/N): "
        read confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # Создание резервной копии
            BACKUP_FILE="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$CONFIG" "$BACKUP_FILE"
            print_success "Резервная копия создана: $BACKUP_FILE"

            # Удаление пользователя
            print_info "Удаление пользователя..."
            TMP_FILE=$(mktemp)
            jq "del(.inbounds[$VLESS_INBOUND_INDEX].settings.clients[] | select(.email == \"$selected_email\"))" "$CONFIG" > "$TMP_FILE"

            if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
                mv "$TMP_FILE" "$CONFIG"
                print_success "Пользователь $selected_email удален"

                # Перезапуск Xray
                restart_xray
            else
                print_error "Ошибка при удалении пользователя"
                rm -f "$TMP_FILE"
            fi
        else
            print_warning "Удаление отменено"
        fi
    else
        print_error "Неверный выбор"
    fi

    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# ----------------------------------------------------------------------------
# НАСТРОЙКА РАСШИРЕННЫХ ПАРАМЕТРОВ
# ----------------------------------------------------------------------------
advanced_config_menu() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                    ADVANCED CONFIGURATION                                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${GREEN}Текущие параметры:${NC}"
    echo "  Network: $NETWORK"
    echo "  Fingerprint: $FINGERPRINT"
    [ -n "$XHTTP_PATH" ] && echo "  Path: /$XHTTP_PATH"
    [ -n "$MODE" ] && echo "  Mode: $MODE"
    [ -n "$FINALMASK" ] && echo "  Finalmask: задан"
    [ -n "$ALPN" ] && echo "  ALPN: $ALPN"
    [ -n "$SPIDERX" ] && echo "  SpiderX: $SPIDERX"
    echo ""
    
    echo -e "${YELLOW}Выберите параметр для настройки:${NC}"
    echo "  1) Transport type (tcp, xhttp, ws, grpc, kcp, httpupgrade)"
    echo "  2) Path"
    echo "  3) Mode (для xhttp: auto, packet-up, stream-up, stream-one)"
    echo "  4) Finalmask (JSON)"
    echo "  5) ALPN (h2,http/1.1 через запятую)"
    echo "  6) SpiderX (путь)"
    echo "  7) Fingerprint (chrome, firefox, safari, random, randomized)"
    echo "  8) Flow (xtls-rprx-vision, xtls-rprx-utls, xtls-rprx-utls-vision)"
    echo "  0) Назад"
    echo ""
    read -p "Ваш выбор (0-8): " adv_choice

    case $adv_choice in
        1)
            echo -n "Введите тип транспорта (tcp/xhttp/ws/grpc/kcp/httpupgrade): "
            read NETWORK
            ;;
        2)
            echo -n "Введите путь (без ведущего /): "
            read XHTTP_PATH
            ;;
        3)
            echo -n "Введите режим (auto/packet-up/stream-up/stream-one): "
            read MODE
            ;;
        4)
            echo -n "Введите Finalmask JSON: "
            read FINALMASK
            ;;
        5)
            echo -n "Введите ALPN (h2,http/1.1): "
            read ALPN
            ;;
        6)
            echo -n "Введите SpiderX путь: "
            read SPIDERX
            ;;
        7)
            echo -n "Введите Fingerprint (chrome/firefox/safari/random/randomized): "
            read FINGERPRINT
            ;;
        8)
            echo -n "Введите Flow (xtls-rprx-vision/xtls-rprx-utls/xtls-rprx-utls-vision): "
            read FLOW
            ;;
        0)
            return
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
    
    print_success "Параметры обновлены"
    read -p "Нажмите Enter для продолжения..."
    advanced_config_menu
}

# ----------------------------------------------------------------------------
# ГЛАВНОЕ МЕНЮ
# ----------------------------------------------------------------------------
show_main_menu() {
    while true; do
        clear
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║                     XRAY REALITY USER MANAGEMENT                          ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo " Server: $DOMAIN:443"
        echo " Users: $CLIENTS_COUNT"
        echo " Transport: $NETWORK"
        [ "$NETWORK" = "xhttp" ] && echo "️  Path: /$XHTTP_PATH"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Доступные действия:${NC}"
        echo -e "  ${BLUE}1${NC}) Просмотр всех пользователей"
        echo -e "  ${BLUE}2${NC}) Добавить нового пользователя"
        echo -e "  ${BLUE}3${NC}) Удалить пользователя"
        echo -e "  ${BLUE}4${NC}) Расширенные настройки"
        echo -e "  ${BLUE}0${NC}) Выход"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -p "Ваш выбор (0-4): " choice

        case $choice in
            1)
                view_users_menu
                ;;
            2)
                add_user
                ;;
            3)
                delete_user
                ;;
            4)
                advanced_config_menu
                ;;
            0)
                echo -e "${GREEN}bye!${NC}"
                exit 0
                ;;
            *)
                print_error "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# ----------------------------------------------------------------------------
init() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться от root"
        print_info "Запустите: sudo $0"
        exit 1
    fi
    check_docker
    install_jq
    install_qrencode
    load_config
}

init
show_main_menu
