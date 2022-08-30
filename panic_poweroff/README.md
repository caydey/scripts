# Panic poweroff

Force turn off your computer instantly as if you just pulled out its plug

Script is required to be run as root, to do this we toggle the setuid bit on the compiled binary

## Build

```
$ gcc panic.c -o panic
# chown root:root panic
# chmod 4711 panic
# mv panic /usr/local/bin
```

now you can set a secret keybind that points to the `/usr/local/bin/panic` executable
