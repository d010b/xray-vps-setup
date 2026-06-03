#!/bin/bash

# Единый скрипт V1.01 управления пользователями xray-vps-setup без marzban
# Функции: просмотр, добавление и удаление

# set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# export RED GREEN YELLOW BLUE NC


IS_MARZBAN="false"
CONFIG=""
DOMAIN=""
PRIVATE_KEY=""
PBK=""
SID=""
XHTTP_PATH=""
NETWORK=""
CLIENTS_COUNT=0 #tst


trap 'echo -e "\n${YELLOW} Прервано пользователем${NC}"; exit 0' INT TERM

print_info() { echo -e "${BLUE} $1${NC}"; }
print_success() { echo -e "${GREEN} $1${NC}"; }
print_error() { echo -e "${RED} $1${NC}"; }
print_warning() { echo -e "${YELLOW} $1${NC}"; }

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

url_encode() {
    printf '%s' "$1" | jq -sRr @uri
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

     #Validate JSON
    if ! jq empty "$CONFIG" 2>/dev/null; then
        print_error "Конфиг файл содержит невалидный JSON"
        exit 1
    fi

     #Get the parameters
    DOMAIN=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG" 2>/dev/null)
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        print_error "Не найден domain в конфиге"
        exit 1
    fi

    PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG" 2>/dev/null)
    if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "null" ]; then
        print_error "Не найден privateKey в конфиге"
        exit 1
    fi

     #Gen PBK
    PBK=$(docker run --rm ghcr.io/xtls/xray-core:latest x25519 -i "$PRIVATE_KEY" 2>/dev/null | grep -E "(PublicKey:|Password \(PublicKey\):)" | head -1 | awk '{print $NF}')
    if [ -z "$PBK" ]; then
        print_error "Не удалось сгенерировать публичный ключ"
        exit 1
    fi

    SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG" 2>/dev/null)
    if [ -z "$SID" ] || [ "$SID" = "null" ]; then
        SID=""
    fi

    XHTTP_PATH=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "$CONFIG" 2>/dev/null | sed 's|^/||')
    if [ -z "$XHTTP_PATH" ] || [ "$XHTTP_PATH" = "null" ]; then
        XHTTP_PATH="xhttp"
    fi

    NETWORK=$(jq -r '.inbounds[0].streamSettings.network' "$CONFIG" 2>/dev/null)
    if [ -z "$NETWORK" ] || [ "$NETWORK" = "null" ]; then
        NETWORK="tcp"
    fi

    CLIENTS_COUNT=$(jq '.inbounds[0].settings.clients | length' "$CONFIG" 2>/dev/null)
}

create_vless_link() {
    local uuid="$1"
    local email="$2"
    local encoded_email=$(url_encode "$email")

    local SID_PARAM=""
    if [ -n "$SID" ]; then
        SID_PARAM="&sid=$SID"
    fi

    if [ "$NETWORK" = "xhttp" ]; then
        echo "vless://$uuid@$DOMAIN:443?encryption=none&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PBK${SID_PARAM}&type=xhttp&path=/$XHTTP_PATH&mode=auto&email=$encoded_email"
    else
        echo "vless://$uuid@$DOMAIN:443?encryption=none&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PBK${SID_PARAM}&flow=xtls-rprx-vision&type=tcp&email=$encoded_email"
    fi
}

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
    done < <(jq -r '.inbounds[0].settings.clients[] | "\(.email)|\(.id)"' "$CONFIG" 2>/dev/null)

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
    done < <(jq -r '.inbounds[0].settings.clients[] | "\(.email)|\(.id)"' "$CONFIG" 2>/dev/null)

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

add_user() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                    ADD NEW XRAY REALITY USER                              ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " Server: $DOMAIN:443"
    echo " Transport: $NETWORK"
    [ "$NETWORK" = "xhttp" ] && echo "️  Path: /$XHTTP_PATH"
    echo ""

    # User name
    while true; do
        echo -n " Enter name for new user (e.g., friend, client1): "
        read USER_EMAIL

        if [ -z "$USER_EMAIL" ]; then
            print_warning "Name не может быть пустым"
            continue
        fi

        if jq -e ".inbounds[0].settings.clients[] | select(.email == \"$USER_EMAIL\")" "$CONFIG" > /dev/null 2>&1; then
            print_error "Пользователь с Name '$USER_EMAIL' уже существует!"
            continue
        fi
        break
    done

    # Gen UUID
    print_info "Генерация UUID для $USER_EMAIL..."
    NEW_UUID=$(generate_uuid)

    if [ -z "$NEW_UUID" ] || [ ${#NEW_UUID} -lt 30 ]; then
        print_error "Не удалось сгенерировать UUID"
        return
    fi

    print_success "UUID сгенерирован: $NEW_UUID"

    # Backup
    BACKUP_FILE="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG" "$BACKUP_FILE"
    print_success "Резервная копия создана: $BACKUP_FILE"

    # Make new user
    if [ "$NETWORK" = "xhttp" ]; then
        NEW_CLIENT="{
            \"id\": \"$NEW_UUID\",
            \"email\": \"$USER_EMAIL\"
        }"
    else
        NEW_CLIENT="{
            \"id\": \"$NEW_UUID\",
            \"email\": \"$USER_EMAIL\",
            \"flow\": \"xtls-rprx-vision\"
        }"
    fi

    # Add new usr
    print_info "Добавление нового пользователя в конфиг..."
    TMP_FILE=$(mktemp)
    jq ".inbounds[0].settings.clients += [$NEW_CLIENT]" "$CONFIG" > "$TMP_FILE"

    if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
        mv "$TMP_FILE" "$CONFIG"
        print_success "Пользователь добавлен в конфиг"
    else
        print_error "Ошибка при добавлении пользователя"
        rm -f "$TMP_FILE"
        return
    fi

    restart_xray

    # VLESS link
    vless_link=$(create_vless_link "$NEW_UUID" "$USER_EMAIL")

    # Result
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                          USER ADDED SUCCESSFULLY!                         ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " New User: $USER_EMAIL"
    echo " UUID: $NEW_UUID"
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

delete_user() {
    clear
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                       DELETE XRAY REALITY USER                            ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    declare -a delete_emails
    declare -a delete_uuids
    local idx=1

    # Get him all
    while IFS='|' read -r email uuid; do
        email=${email:-"no-email"}
        uuid=${uuid:-"no-uuid"}

        if [ "$uuid" != "no-uuid" ] && [ ${#uuid} -ge 30 ]; then
            delete_emails+=("$email")
            delete_uuids+=("$uuid")
            ((idx++))
        fi
    done < <(jq -r '.inbounds[0].settings.clients[] | "\(.email)|\(.id)"' "$CONFIG" 2>/dev/null)

    # User test
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
            # Backup
            BACKUP_FILE="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$CONFIG" "$BACKUP_FILE"
            print_success "Резервная копия создана: $BACKUP_FILE"

            # Del usr
            print_info "Удаление пользователя..."
            TMP_FILE=$(mktemp)
            jq "del(.inbounds[0].settings.clients[] | select(.email == \"$selected_email\"))" "$CONFIG" > "$TMP_FILE"

            if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
                mv "$TMP_FILE" "$CONFIG"
                print_success "Пользователь $selected_email удален"

                # Restart Xray
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

show_main_menu() {
    while true; do
        clear
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║                     XRAY REALITY USER MANAGEMENT                          ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo " Server: $DOMAIN:443"
        echo " Users: $CLIENTS_COUNT"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Доступные действия:${NC}"
        echo -e "  ${BLUE}1${NC}) Просмотр всех пользователей"
        echo -e "  ${BLUE}2${NC}) Добавить нового пользователя"
        echo -e "  ${BLUE}3${NC}) Удалить пользователя"
        echo -e "  ${BLUE}0${NC}) Выход"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -p "Ваш выбор (1-3): " choice

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
