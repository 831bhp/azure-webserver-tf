Install Pkgs:
  pkg.installed:
    - pkgs:
      - apache2

Enable apache service:
  service.enabled:
    - name: apache2

