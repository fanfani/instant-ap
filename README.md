# instant-ap

Setup your GNU/Linux box as an access point: dumb-proof-easy script + confs

features:

- **minimal**, a single bash script and two very tiny conf files. Very easy to edit.

- **minimal requirements**, just dnsmasq and hostapd.

- **self-contained**, everything you need in one dir. No need to edit system-wide configurations.

- **init style control script**, with the familiar "start|stop|status" syntax.


*USAGE:*

```
# ./instant-ap.sh start
```

defaults are as follows:

- wan interface: ppp0

- radio interface: wlan0

- ssid: instant-ap

- security: open ap

- lan settings: 10.0.0.0/24

- dhcp lease: 12h
