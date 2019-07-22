#!/usr/bin/env bash

# Nginx installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

if [ "$(type -t run)" != "function" ]; then
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

function init_nginx_install() {
    echo ""
    echo "Welcome to Nginx Installation..."
    echo ""

    if "${AUTO_INSTALL}"; then
        # Set default Iptables-based firewall configutor engine.
        SELECTED_NGINX_INSTALLER=${NGINX_INSTALLER:-"source"}
    else
        # Install Nginx custom
        echo "Available Nginx installer to use:"
        echo "  1). Install from Repository"
        echo "  2). Compile from Source (default)"
        echo "------------------------------------"
        while [[ ${SELECTED_NGINX_INSTALLER} != "1" && ${SELECTED_NGINX_INSTALLER} != "2" \
            && ${SELECTED_NGINX_INSTALLER} != "repo" && ${SELECTED_NGINX_INSTALLER} != "source" ]]; do
            read -p "Select an option [1-2]: " -i ${NGINX_INSTALLER} -e SELECTED_NGINX_INSTALLER
    	done

        echo ""
    fi

    case ${SELECTED_NGINX_INSTALLER} in
        1|repo)
            echo "Installing Nginx from package repository..."
            run apt-get install -y --allow-unauthenticated ${NGX_PACKAGE}
        ;;

        2|source|*)
            echo "Installing Nginx from source..."
            run ${BASEDIR}/install_nginx_from_source.sh -v latest-stable -n stable \
                --dynamic-module --extra-modules -y

            echo ""
            echo "Configuring Nginx extra modules..."
            # Custom Nginx dynamic modules configuration
            if [[ -f /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-brotli-filter.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_brotli_filter_module.so\";" > \
                    /etc/nginx/modules-available/mod-http-brotli-filter.conf'
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_brotli_static_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-brotli-static.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_brotli_static_module.so\";" > \
                    /etc/nginx/modules-available/mod-http-brotli-static.conf '
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_cache_purge_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-cache-purge.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_cache_purge_module.so\";" > \
                    /etc/nginx/modules-available/mod-http-cache-purge '
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_geoip_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_geoip_module.so\";" > \
                    /etc/nginx/modules-available/mod-http-geoip.conf'
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_image_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-image-filter.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_image_filter_module.so\";" > \
                    /etc/nginx/modules-available/mod-http-image-filter.conf'
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_mail_module.so && \
                ! -f /etc/nginx/modules-available/mod-mail.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_mail_module.so\";" > \
                    /etc/nginx/modules-available/mod-mail.conf'
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_http_xslt_filter_module.so && \
                ! -f /etc/nginx/modules-available/mod-http-xslt-filter.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_xslt_filter_module.so\";" > \
                    /etc/nginx/modules-available/mod-http-xslt-filter.conf'
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_pagespeed.so && \
                ! -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_pagespeed.so\";" > \
                    /etc/nginx/modules-available/mod-pagespeed.conf'
            fi

            if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so && \
                ! -f /etc/nginx/modules-available/mod-stream.conf ]]; then
                run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_stream_module.so\";" > \
                    /etc/nginx/modules-available/mod-stream.conf'
            fi

            # Enable Nginx Dynamic Module
            echo ""
            while [[ $ENABLE_NGXDM != "y" && $ENABLE_NGXDM != "n" ]]; do
                read -p "Enable Nginx dynamic modules? [y/n]: " -e ENABLE_NGXDM
            done
            if [[ "$ENABLE_NGXDM" == Y* || "$ENABLE_NGXDM" == y* ]]; then
                if [[ -f /etc/nginx/modules-available/mod-pagespeed.conf && \
                    ! -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
                    run ln -s /etc/nginx/modules-available/mod-pagespeed.conf /etc/nginx/modules-enabled/50-mod-pagespeed.conf
                fi

                #run ln -s /etc/nginx/modules-available/mod-http-geoip.conf /etc/nginx/modules-enabled/50-mod-http-geoip.conf
            fi

            # Nginx init script
            if [ ! -f /etc/init.d/nginx ]; then
                run cp etc/init.d/nginx /etc/init.d/
                run chmod ugo+x /etc/init.d/nginx
            fi

            # Nginx systemd script
            if [ ! -f /lib/systemd/system/nginx.service ]; then
                run cp etc/systemd/nginx.service /lib/systemd/system/

                if [ ! -f /etc/systemd/system/nginx.service ]; then
                    run link -s /lib/systemd/system/nginx.service /etc/systemd/system/nginx.service
                fi

                # Reloading daemon
                run systemctl daemon-reload
            fi
        ;;
    esac

    # Create Nginx directories.
    if [ ! -d /etc/nginx/modules-available ]; then
        run mkdir /etc/nginx/modules-available
    fi

    if [ ! -d /etc/nginx/modules-enabled ]; then
        run mkdir /etc/nginx/modules-enabled
    fi

    if [ ! -d /etc/nginx/sites-available ]; then
        run mkdir /etc/nginx/sites-available
    fi

    if [ ! -d /etc/nginx/sites-enabled ]; then
        run mkdir /etc/nginx/sites-enabled
    fi

    # Copy custom Nginx Config
    if [ -f /etc/nginx/nginx.conf ]; then
        run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old
    fi

    run cp -f etc/nginx/charset /etc/nginx/
    run cp -f etc/nginx/comp_brotli /etc/nginx/
    run cp -f etc/nginx/comp_gzip /etc/nginx/
    run cp -f etc/nginx/fastcgi_cache /etc/nginx/
    run cp -f etc/nginx/fastcgi_https_map /etc/nginx/
    run cp -f etc/nginx/fastcgi_params /etc/nginx/
    run cp -f etc/nginx/http_cloudflare_ips /etc/nginx/
    run cp -f etc/nginx/http_proxy_ips /etc/nginx/
    run cp -f etc/nginx/nginx.conf /etc/nginx/
    run cp -f etc/nginx/proxy_cache /etc/nginx/
    run cp -f etc/nginx/proxy_params /etc/nginx/
    run cp -f etc/nginx/upstream /etc/nginx/
    run cp -fr etc/nginx/includes/ /etc/nginx/
    run cp -fr etc/nginx/vhost/ /etc/nginx/
    run cp -fr etc/nginx/ssl/ /etc/nginx/

    if [ -f /etc/nginx/sites-available/default ]; then
        run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old
    fi

    run cp -f etc/nginx/sites-available/default /etc/nginx/sites-available/

    if [ -f /etc/nginx/sites-enabled/default ]; then
        run unlink /etc/nginx/sites-enabled/default
    fi

    if [ -f /etc/nginx/sites-enabled/01-default ]; then
        run unlink /etc/nginx/sites-enabled/01-default
    fi

    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

    if [ -d /usr/share/nginx/html ]; then
        run chown -hR www-data:root /usr/share/nginx/html
    fi

    # Nginx cache directory
    if [ ! -d /var/cache/nginx ]; then
        run mkdir /var/cache/nginx
        run chown -hR www-data:root /var/cache/nginx
    fi

    if [ ! -d /var/cache/nginx/fastcgi_cache ]; then
        run mkdir /var/cache/nginx/fastcgi_cache
        run chown -hR www-data:root /var/cache/nginx/fastcgi_cache
    fi

    if [ ! -d /var/cache/nginx/proxy_cache ]; then
        run mkdir /var/cache/nginx/proxy_cache
        run chown -hR www-data:root /var/cache/nginx/proxy_cache
    fi

    # Final test.
    echo ""

    if "${DRYRUN}"; then
        IP_SERVER="127.0.0.1"
        warning "Nginx web server installed in dryrun mode."
    else
        IP_SERVER=$(get_ip_addr)

        # Make default server accessible from IP address.
        run sed -i "s|localhost.localdomain|${IP_SERVER}|g" /etc/nginx/sites-available/default

        # Restart Nginx server
        echo "Starting Nginx web server..."
        if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
            run service nginx reload -s
            status "Nginx web server restarted successfully."
        elif [[ -n $(which nginx) ]]; then
            run service nginx start

            if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
                status "Nginx web server started successfully."
            else
                warning "Something wrong with Nginx installation."
            fi
        fi
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which nginxx) && -d /etc/nginx/sites-available ]]; then
    warning -e "\nNginx web server already exists. Installation skipped..."
else
    init_nginx_install "$@"
fi
