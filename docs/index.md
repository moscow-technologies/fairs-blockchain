# Инструкция по использованию локальной блокчейн-ноды
Описание установки блокчейн-ноды  для [проекта](https://www.mos.ru/blockchain-yarmarki/).
Для развертывания локального узла блокчейн-сети необходима установка специализированного ПО [Parity](https://www.parity.io) и запуск его со специальной конфигурацией. Все инструкции по установке и просмотру данных ниже.

## Установка блокчейн-ноды

### Windows
  - Скачайте и запустите [установочный пакет](https://github.com/moscow-technologies/fairs-blockchain/releases/download/3.4/Parity.UI.Fairs.Setup.3.4.exe)

### MacOS
  - Скачайте и запустите [установочный пакет](https://github.com/moscow-technologies/fairs-blockchain/releases/download/3.4/Parity.UI.Fairs-3.4.dmg)

## Предварительная настройка

Чтобы получить доступ к возможностям приложения, необходимо внимательно прочитать и принять условия лицензионного соглашения (отметив галочку внизу окна):

![Принятие лицензионного соглашения](https://raw.githubusercontent.com/moscow-technologies/fairs-blockchain/master/docs/images/accept-licence.png)

## Работа с интерфейсом Parity UI
Приложение Parity UI предоставляет ряд системных и прикладных интерфейсов для работы с локальной блокчейн-нодой. 
Приложения для Parity UI называются `Dapp` *(англ. distributed application)* - пользовательский интерфейс, опирающийся на логику смарт-контрактов и работающий с блокчейн-нодой.
Для корректной работы приложения необходимо подключение к сети интернет.

### Dapp *Ярмарки выходного дня* 
Прикладной интерфейс поиска и просмотра заявок на участие в ярмарках выходного дня. 
Функционал  аналогичен размещенному в разделе  [https://www.mos.ru/blockchain-yarmarki](https://www.mos.ru/blockchain-yarmarki/), но работает с локальной нодой блокчейна, синхронизированной с блокчейн-сетью.
![Приложение Ярмарки выходного дня](https://raw.githubusercontent.com/moscow-technologies/fairs-blockchain/master/docs/images/fairs-dapp-screen.png)

### Dapp *Node Status*
Системный интерфейс блокчейн-ноды, позволяющий узнать статус синхронизации, количество подключенных к ноде узлов, количество блоков в блокчейне, просмотреть системные логи ноды.
![Приложение Node Status](https://raw.githubusercontent.com/moscow-technologies/fairs-blockchain/master/docs/images/node-status-screen.png)
