Debugging `cloudflared` daemon for Cloudflare Tunnels created using Named Tunnels. Requires Tunnels configured with `metrics: localhost:5432`. Tested only on CentOS 7.

```
./cloudflared-debug.sh 

Usage:

./cloudflared-debug.sh debug tunnel_name
```