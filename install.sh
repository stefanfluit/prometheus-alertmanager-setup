#!/usr/bin/env bash

# Currently only for CentOS 8.

# Set Bash behaviour
set -o errexit      # Exit on uncaught errors
set -o pipefail 	# Fail pipe on first error

declare SLACK_URL="${1}"

download_configs() {
    local alert_rules="(https://raw.githubusercontent.com/stefanfluit/prometheus-alertmanager-setup/master/files/rules.yml"
    local prometheus_config="https://raw.githubusercontent.com/stefanfluit/prometheus-alertmanager-setup/master/files/prometheus.yml"
    local alertmanager_config="https://raw.githubusercontent.com/stefanfluit/prometheus-alertmanager-setup/master/files/alertmanager.yml"
    # Downloading the configs
    if [ "${1}" == '--prometheus-config' ]; then
        curl -fsSL "${prometheus_config}" > /etc/prometheus/prometheus.yml
    fi
    if [ "${1}" == '--alertmanager-rules' ]; then
        curl -fsSL "${alert_rules}" > /etc/prometheus/rules.yml
    fi
    if [ "${1}" == '--alertmanager-config' ]; then
        curl -fsSL "${alertmaneger_config}" > /etc/alertmanager/alertmanager.yml
    fi
}

init_user_files_firewall() {
    local user_parameter
    user_parameter="${1}"
    chown -R "${user_parameter}":"${user_parameter}" "/etc/${user_parameter}"
    chown -R "${user_parameter}":"${user_parameter}" "/usr/local/bin/${user_parameter}"
    if [ "${user_parameter}" == 'prometheus' ]; then
        firewall-cmd --add-port=9090/tcp --permanent >> /dev/null && printf "Succesfully added firewall port.\n"
        useradd --no-create-home --shell /bin/false prometheus
    fi
    if [ "${user_parameter}" == 'alertmanager' ]; then
        firewall-cmd --add-port=9093/tcp --permanent >> /dev/null && printf "Succesfully added firewall port.\n"
        useradd --no-create-home --shell /bin/false alertmanager
    fi
    if [ "${user_parameter}" == 'node_exporter' ]; then
        firewall-cmd --add-port=9100/tcp --permanent >> /dev/null && printf "Succesfully added firewall port.\n"
        useradd --no-create-home --shell /bin/false node_exporter
    fi
    firewall-cmd --reload >> /dev/null && printf "Firewall reloaded.\n"
}

_install_if() {
    # Installing Prometheus and Alertmanager, if not available.
    local lan_ip
    lan_ip=$(hostname -I | awk '{print $1}')
    local systemd_file_prometheus="https://gist.githubusercontent.com/stefanfluit/caac159c31f0bd7291882ba8d5182230/raw/56c130b02c28a3251e0039290ad683e1c69cf0f1/prometheus.service"
    local systemd_file_alertmanager="https://gist.githubusercontent.com/stefanfluit/e5bd33c267a54320f118a3d8e0926926/raw/65f6a2acb770c7faafee33191bcb323e7db6d4bd/alertmanager.service"
    local systemd_file_node_exporter="https://gist.githubusercontent.com/stefanfluit/8d1c7fb1b2af8da487295ada4e64060c/raw/c870e1000b1b22f87cfb5f229bb878f4f786e07b/node_exporter.service"
    local FILE_PROMETHEUS="/usr/local/bin/prometheus"
    local FILE_ALERTMANAGER="/usr/local/bin/alertmanager"
    local FILE_NODE_EXPORTER="/usr/local/bin/node_exporter"
    if [[ -f "${FILE_PROMETHEUS}" ]]; then
        printf "Prometheus seems to be installed.\n"
    else
        # Download latest version of Prometheus.
        printf "Downloading Prometheus..\n" && curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest   | grep browser_download_url   | grep linux-amd64   | cut -d '"' -f 4   | wget -qi -
        tar xvf  $(find $(pwd) -name 'prometheus*.tar.gz')
        cp $(find $(pwd) -name 'prometheus*' -type d)/prometheus /usr/local/bin/
        cp $(find $(pwd) -name 'prometheus*' -type d)/promtool /usr/local/bin/
        cp $(find $(pwd) -name 'prometheus*' -type d)/consoles/ /etc/prometheus
        cp $(find $(pwd) -name 'prometheus*' -type d)/console_libraries/ /etc/prometheus
        curl -s "${systemd_file_prometheus}" >> /etc/system/system/prometheus.service
        sed -i "s/x.x.x.x/${lan_ip}/g" /etc/system/system/prometheus.service && systemctl daemon-reload
        download_configs "--prometheus-config"
        sed -i "s/x.x.x.x/${lan_ip}/g" /etc/prometheus/prometheus.yml
        init_user_files_firewall "prometheus"
    fi
    if [[ -f "${FILE_ALERTMANAGER}" ]]; then
        printf "Alertmanager seems to be installed.\n"
    else
        # Download latest version of Alertmanager.
        printf "Downloading Alertmanager..\n" && curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest   | grep browser_download_url   | grep linux-amd64   | cut -d '"' -f 4   | wget -qi -
        tar xvf  $(find $(pwd) -name 'alertmanager*.tar.gz')
        cp $(find $(pwd) -name 'alertmanager*' -type d)/alertmanager /usr/local/bin
        cp $(find $(pwd) -name 'alertmanager*' -type d)/amtool /usr/local/bin
        curl -s "${systemd_file_alertmanager}" >> /etc/system/system/alertmanager.service
        sed -i "s/x.x.x.x/${lan_ip}/g" /etc/system/system/alertmanager.service && systemctl daemon-reload
        mkdir /etc/alertmanager && download_configs "--alertmanager-config"
        sed -i "s/x.x.x.x/${SLACK_URL}/g" /etc/alertmanager/alertmanager.yml
        init_user_files_firewall "alertmanager"
    fi
    if [[ -f "${FILE_NODE_EXPORTER}" ]]; then
        printf "Node_exporter seems to be installed.\n"
    else
    #   Download latest version of Node_exporter.
        printf "Downloading node_exporter..\n" && curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest   | grep browser_download_url   | grep linux-amd64   | cut -d '"' -f 4   | wget -qi -
        tar -xf  $(find $(pwd) -name 'node_exporter*.tar.gz')
        cp $(find $(pwd) -name 'node_exporter*' -type d)/node_exporter /usr/local/bin
        curl -s "${systemd_file_node_exporter}" >> /etc/system/system/node_exporter.service && systemctl daemon-reload
        init_user_files_firewall "alertmanager"
    fi
    systemctl enable prometheus; systemctl enable node_exporter; systemctl enable alertmanager
    systemctl start prometheus; systemctl start node_exporter; systemctl start alertmanager

    printf "Prometheus at: http://%s:9090\n" "${lan_ip}"
    printf "Alertmanager at: http://%s:9093\n" "${lan_ip}"
    printf "Node_exporter at: http://%s:9100\n" "${lan_ip}"
}

main() {
    if [[ $# -eq 0 ]]
    then
        printf "No arguments supplied.\nRun like: ./install.sh <Slack webhook URL>\n"
        exit 1;
    fi
    _install_if
}

main
