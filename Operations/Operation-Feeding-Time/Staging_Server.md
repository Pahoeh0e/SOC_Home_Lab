## Infrastructure: Feeding_Time Staging Server

A Dockerized Nginx server on the Wazuh manager acts as a realistic 
payload staging and exfiltration target:

```bash
# Deployment
sudo docker run -d \
  --name Feeding_Time-c2 \
  --restart unless-stopped \
  -p 8080:80 \
  -v /opt/feeding_time-nginx/logs:/var/log/nginx \
  -v /opt/feeding_time-nginx/www:/usr/share/nginx/html \
  --memory="128m" \
  --cpus="0.5" \
  nginx:alpine

```

## Payloads

Realistic paylods under '/opt/shadowdrop-nginx/www/' including:

-    payload.ps1
-    payload.txt
-    exfil.txt
-    stage.ps1
