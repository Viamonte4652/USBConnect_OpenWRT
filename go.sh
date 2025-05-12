#!/bin/bash

# Скрипт настройки USB-флешки как основного хранилища для OpenWRT
# Версия 1.0

# Функция для логирования
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Проверка прав суперпользователя
if [ "$(id -u)" != "0" ]; then
   log "Этот скрипт должен быть запущен с правами root" 
   exit 1
fi

# Путь к устройству (может потребоваться изменение)
DEVICE="/dev/sda"

# Функция обработки ошибок
error_exit() {
    log "ОШИБКА: $1"
    exit 1
}

# Обновление и установка пакетов
update_packages() {
    log "Обновление пакетов..."
    opkg update || error_exit "Не удалось обновить пакеты"
    
    log "Установка необходимых пакетов..."
    opkg install block-mount kmod-usb-storage kmod-fs-ext4 e2fsprogs fdisk || \
    error_exit "Не удалось установить необходимые пакеты"
}

# Подготовка устройства
prepare_device() {
    log "Очистка существующей разметки диска..."
    dd if=/dev/zero of=$DEVICE bs=512 count=1 || \
    error_exit "Не удалось очистить таблицу разделов"
    
    log "Создание нового раздела..."
    (
    echo o     # Создать новую пустую таблицу разделов
    echo n     # Создать новый раздел
    echo p     # Первичный раздел
    echo 1     # Номер раздела
    echo       # Начальный сектор по умолчанию
    echo       # Конечный сектор по умолчанию
    echo w     # Записать изменения
    ) | fdisk $DEVICE || error_exit "Не удалось создать раздел"
    
    # Небольшая пауза для обновления системы
    sleep 2
}

# Форматирование раздела
format_partition() {
    log "Форматирование раздела в ext4..."
    mkfs.ext4 "${DEVICE}1" || error_exit "Не удалось отформатировать раздел"
}

# Монтирование и перенос данных
mount_and_transfer() {
    # Создание точки монтирования
    mkdir -p /mnt/usb || error_exit "Не удалось создать точку монтирования"
    
    # Монтирование
    mount -t ext4 "${DEVICE}1" /mnt/usb || error_exit "Не удалось смонтировать раздел"
    
    # Перенос данных overlay
    log "Перенос данных overlay..."
    tar -C /overlay -cvf - . | tar -C /mnt/usb -xf - || \
    error_exit "Не удалось перенести данные overlay"
}

# Настройка автомонтирования
configure_fstab() {
    log "Настройка автомонтирования..."
    block detect > /etc/config/fstab || \
    error_exit "Не удалось сгенерировать fstab"
    
    uci set fstab.@mount[0].target='/overlay'
    uci set fstab.@mount[0].enabled='1'
    uci commit fstab || error_exit "Не удалось настроить fstab"
    
    # Включение автозагрузки
    /etc/init.d/fstab enable || error_exit "Не удалось включить автозагрузку fstab"
}

# Настройка opkg
configure_opkg() {
    log "Настройка opkg..."
    mkdir -p /mnt/usb/packages || error_exit "Не удалось создать директорию пакетов"
    
    # Добавление настроек в opkg.conf
    echo "dest usb /mnt/usb/packages" >> /etc/opkg.conf
    echo "option overlay_root /mnt/usb" >> /etc/opkg.conf
}

# Главная функция
main() {
    log "Начало настройки USB-хранилища для OpenWRT"
    
    update_packages
    prepare_device
    format_partition
    mount_and_transfer
    configure_fstab
    configure_opkg
    
    log "Настройка завершена. Перезагрузка..."
    reboot
}

# Запуск главной функции
main
